local navic = require("nvim-navic")
local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
local config = require("barbecue.config")
local utils = require("barbecue.utils")

local M = {}

---whether winbar is visible
---@type boolean
local visible = true

---mapping of `winnr` to its `winbar` state before being set
---@type table<number, string>
local affected_wins = {}

---returns dirname of `bufnr`
---@param bufnr number
---@return barbecue.Entry[]|nil
local function get_dirname(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local dirname = vim.fn.fnamemodify(filename, config.user.modifiers.dirname .. ":h")

  local entries = {}

  if dirname == "." then return nil end
  if dirname ~= "/" and dirname:sub(1, 1) == "/" then
    dirname:sub(2)
    table.insert(entries, {
      text = {
        "/",
        highlight = "NavicText",
      },
    })
  end

  for _, dir in ipairs(vim.split(dirname, "/")) do
    table.insert(entries, {
      text = {
        dir,
        highlight = "NavicText",
      },
    })
  end

  return entries
end

---returns basename of `bufnr`
---@param winnr number
---@param bufnr number
---@return barbecue.Entry|nil
local function get_basename(winnr, bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local basename = vim.fn.fnamemodify(filename, config.user.modifiers.basename .. ":t")
  if basename == "" then return nil end

  local icon, icon_highlight
  if devicons_ok then
    icon, icon_highlight = devicons.get_icon_by_filetype(vim.bo[bufnr].filetype)
  end

  return {
    text = {
      basename,
      highlight = "NavicText",
    },
    icon = {
      icon,
      highlight = icon_highlight,
    },
    click = string.format("v:lua.require'barbecue.mouse'.navigate_%d_1_0", winnr),
  }
end

---returns context of `bufnr`
---@param winnr number
---@param bufnr number
---@return barbecue.Entry[]|nil
local function get_context(winnr, bufnr)
  if not navic.is_available() then return nil end

  local nestings = navic.get_data(bufnr)
  if nestings == nil then return nil end

  return vim.tbl_map(function(nesting)
    return {
      text = {
        nesting.name,
        highlight = "NavicText",
      },
      icon = {
        config.user.kinds[nesting.type],
        highlight = "NavicIcons" .. nesting.type,
      },
      click = string.format(
        "v:lua.require'barbecue.mouse'.navigate_%d_%d_%d",
        winnr,
        nesting.scope.start.line,
        nesting.scope.start.character
      ),
    }
  end, nestings)
end

---toggles visibility
---@param shown boolean?
function M.toggle(shown)
  if shown == nil then shown = not visible end

  visible = shown
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    M.update(winnr)
  end
end

---@async
---updates winbar on `winnr`
---@param winnr number?
function M.update(winnr)
  winnr = winnr or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winnr)

  if
    not vim.tbl_contains(config.user.include_buftypes, vim.bo[bufnr].buftype)
    or vim.tbl_contains(config.user.exclude_filetypes, vim.bo[bufnr].filetype)
    or vim.api.nvim_win_get_config(winnr).relative ~= ""
  then
    if affected_wins[winnr] ~= nil then
      vim.wo[winnr].winbar = affected_wins[winnr]
      affected_wins[winnr] = nil
    end

    return
  end

  if not visible then
    vim.wo[winnr].winbar = nil
    return
  end

  vim.schedule(function()
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or not vim.api.nvim_win_is_valid(winnr)
      or bufnr ~= vim.api.nvim_win_get_buf(winnr)
    then
      return
    end

    local dirname = get_dirname(bufnr)
    local basename = get_basename(winnr, bufnr)
    local context = get_context(winnr, bufnr)
    if basename == nil then return end

    ---@type barbecue.Entry[]
    local entries = {}
    utils.tbl_merge(entries, dirname or {}, { basename }, context or {})

    local winbar = " "
    for i, entry in ipairs(entries) do
      winbar = winbar
        .. (entry.click == nil and "" or "%@" .. utils.exp_escape(entry.click) .. "@")
        .. (entry.icon == nil and "" or "%#" .. entry.icon.highlight .. "#" .. utils.exp_escape(entry.icon[1]) .. " ")
        .. ("%#" .. entry.text.highlight .. "#" .. utils.exp_escape(entry.text[1]))
        .. (entry.click == nil and "" or "%X")
      if i < #entries then winbar = winbar .. " %#NavicSeparator#" .. config.user.symbols.separator .. " " end
    end

    local custom_section = config.user.custom_section(bufnr)
    if type(custom_section) == "string" then winbar = winbar .. "%=" .. custom_section .. " " end

    affected_wins[winnr] = vim.wo[winnr].winbar
    vim.wo[winnr].winbar = winbar
  end)
end

return M
