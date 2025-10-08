-- IDE Layout Command
-- Creates a layout with nvim-tree on the left (1/4 width)
-- and a split editor/terminal on the right (3/4 width)

local M = {}

function M.setup_ide_layout()
  -- Close all windows except current
  vim.cmd("only")

  -- Open nvim-tree on the left
  vim.cmd("NvimTreeOpen")

  -- Move to the right window (main editor area)
  vim.cmd("wincmd l")

  -- Create horizontal split for terminal at bottom
  vim.cmd("split")

  -- Move to bottom split and resize to 1/5 of height
  vim.cmd("wincmd j")
  local total_height = vim.o.lines
  local term_height = math.floor(total_height * 0.20)
  vim.cmd("resize " .. term_height)

  -- Open terminal in bottom split
  vim.cmd("terminal")
  vim.cmd("startinsert")

  -- Move back to top split (editor)
  vim.cmd("wincmd k")
end

-- Create the :IDE command
vim.api.nvim_create_user_command("IDE", M.setup_ide_layout, {})

return M
