local codeBlock = require('mintlify_utils').codeBlock

-- quarto.log.output('---X---') 
local reactPreamble = pandoc.List()

function capitalizeFirstLetter(str)
  return (str:gsub("^%l", string.upper))
end

function castToMintlifyCallout(str)
  if str == "caution" or str == "danger" then
    return "Warning"
  else
    return capitalizeFirstLetter(str)
  end
end

local function addPreamble(preamble)
  if not reactPreamble:includes(preamble) then
    reactPreamble:insert(preamble)
  end
end

local function jsx(content)
  -- quarto.log.output('------') 
  -- quarto.log.output(content)  
  -- quarto.log.output('------')  
  return pandoc.RawBlock("markdown", content)
end

local function tabset(node, filter)
  -- note groupId
  local groupId = ""
  local group = node.attr.attributes["group"]
  if group then
    groupId = ([[ groupId="%s"]]):format(group)
  end

  -- quarto.log.output('------') 
  -- quarto.log.output(node.title)  
  -- quarto.log.output('------')  

  -- create tabs
  local tabs = pandoc.Div({})
  tabs.content:insert(jsx("<Tabs" .. groupId .. ">"))

  -- iterate through content
  for i = 1, #node.tabs do
    local content = node.tabs[i].content
    local title = node.tabs[i].title

    tabs.content:insert(jsx(([[<TabItem value="%s">]]):format(pandoc.utils.stringify(title))))
    local result = quarto._quarto.ast.walk(content, filter)
    if type(result) == "table" then
      tabs.content:extend(result)
    else
      tabs.content:insert(result)
    end
    tabs.content:insert(jsx("</TabItem>"))
  end

  -- end tab and tabset
  tabs.content:insert(jsx("</Tabs>"))

  -- ensure we have required deps
  addPreamble("import Tabs from '@theme/Tabs';")
  addPreamble("import TabItem from '@theme/TabItem';")

  return tabs
end

function Writer(doc, opts)
  -- quarto.log.output('---Z---') 
  -- quarto.log.output(doc) - will get stuck
  -- quarto.utils.dump(doc) -- this works
  -- quarto.utils.dump(opts)
  local filter
  filter = {
    CodeBlock = codeBlock,

    DecoratedCodeBlock = function(node)
      -- quarto.log.output(node)
      local el = node.code_block
      return codeBlock(el, node.filename)
    end,

    Tabset = function(node)
      return tabset(node, filter)
    end,

    RawBlock = function (rawBlock)
      -- quarto.utils.dump(rawBlock.text)
      -- We just "pass-through" raw blocks of type "confluence"
      if(rawBlock.format == 'plotly') then
        quarto.utils.dump("Plotly in filter")
        return pandoc.RawBlock('html', rawBlock.text)
      end

      -- Raw blocks inclding arbirtary HTML like JavaScript are not supported in CSF
      return ""
    end,

    -- Plain = function(node) 
    --   quarto.log.output('------')      
    --   quarto.utils.dump(node.text)
    -- end,

    Callout = function(node)      
      -- quarto.log.output('------')      
      -- quarto.log.output(node.t)
      -- quarto.log.output(node.title)
      -- quarto.log.output(type(node.content))
      -- quarto.log.output('------')
      local admonition = pandoc.Div({})
      local mintlifyCallout = castToMintlifyCallout(node.type)
      admonition.content:insert(jsx("<" .. mintlifyCallout .. ">"))
      if node.title then
        admonition.content:insert(pandoc.Header(3, node.title))                
      end
      local content = node.content
      -- quarto.log.output(type(content))
      if type(content) == "table" then
        admonition.content:extend(content)
        -- quarto.log.output("-----Table content-----")
        -- quarto.log.output(content)
      else
        admonition.content:insert(content)
      end
      -- quarto.log.output(content)
      admonition.content:insert(jsx("</" .. mintlifyCallout .. ">"))
      return admonition
    end
  }

  doc = quarto._quarto.ast.walk(doc, filter)

  -- insert react preamble if we have it
  if #reactPreamble > 0 then
    local preamble = table.concat(reactPreamble, "\n")
    doc.blocks:insert(1, pandoc.RawBlock("markdown", preamble .. "\n"))
  end

  local extensions = {
    yaml_metadata_block = true,
    pipe_tables = true,
    footnotes = true,
    tex_math_dollars = true,
    raw_html = true,
    all_symbols_escapable = true,
    backtick_code_blocks = true,
    space_in_atx_header = true,
    intraword_underscores = true,
    lists_without_preceding_blankline = true,
    shortcut_reference_links = true,
  }

  return pandoc.write(doc, {
    format = 'markdown_strict',
    extensions = extensions
  }, opts)
end