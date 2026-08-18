-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.fileencoding = "utf-8"

-- 剪貼簿：處理複製問題。wl-copy 失敗就用 OSC 52 送到客戶端終端機。
local osc52 = require("vim.ui.clipboard.osc52")

-- wl-clipboard 用 --primary 對應 nvim 的 "*"，預設（不加旗標）對應 "+"
local function wl_args(cmd, reg)
  local args = { cmd }
  if reg == "*" then
    table.insert(args, "--primary")
  end
  return args
end

local function copy(reg)
  return function(lines, regtype)
    local args = wl_args("wl-copy", reg)
    -- 固定 text/plain，不讓 wl-copy 依內容自己猜 MIME type
    table.insert(args, "--type")
    table.insert(args, "text/plain")
    vim.fn.system(args, table.concat(lines, "\n"))
    -- 非 0 = 沒有可用的 Wayland seat，改用 OSC 52 把資料送到客戶端的終端機
    if vim.v.shell_error ~= 0 then
      osc52.copy(reg)(lines, regtype)
    end
  end
end

local function paste(reg)
  return function()
    local args = wl_args("wl-paste", reg)
    -- wl-paste 預設會補結尾換行，不拔掉每次貼上都會多一行
    table.insert(args, "--no-newline")
    local out = vim.fn.system(args)
    if vim.v.shell_error == 0 then
      return vim.split(out, "\n")
    end
    return 0
  end
end

vim.g.clipboard = {
  name = "wl-clipboard with OSC 52 fallback (copy only)",
  copy = { ["+"] = copy("+"), ["*"] = copy("*") },
  paste = { ["+"] = paste("+"), ["*"] = paste("*") },
}
-- yank/paste 不加暫存器前綴時直接走 "+"
vim.opt.clipboard = "unnamedplus"
