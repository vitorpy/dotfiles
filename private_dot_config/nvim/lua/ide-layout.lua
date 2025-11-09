-- IDE Layout Command
-- Creates a layout with nvim-tree on the left (1/4 width)
-- and a split editor/terminal on the right (3/4 width)

local M = {}

function M.setup_ide_layout()
  -- Close all windows except current (ignore errors from floating windows)
  pcall(function() vim.cmd("only") end)

  -- Close nvim-tree if open
  pcall(function() vim.cmd("NvimTreeClose") end)

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

  -- Move back to top split (editor)
  vim.cmd("wincmd k")

  -- Setup autocommand to quit when only tree and terminal are left
  vim.api.nvim_create_autocmd("BufDelete", {
    group = vim.api.nvim_create_augroup("IDEAutoQuit", { clear = true }),
    callback = function()
      -- Small delay to let buffer deletion complete
      vim.defer_fn(function()
        local buf_list = vim.api.nvim_list_bufs()
        local has_normal_buffer = false

        for _, buf in ipairs(buf_list) do
          -- Only check loaded and valid buffers
          if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_is_valid(buf) then
            local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
            local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
            local bufname = vim.api.nvim_buf_get_name(buf)

            -- Check if it's a normal editable buffer (not tree, not terminal, not special)
            if buftype == "" and filetype ~= "NvimTree" and bufname ~= "" then
              has_normal_buffer = true
              break
            end
          end
        end

        -- If no normal buffers left, quit vim
        if not has_normal_buffer then
          vim.cmd("qall")
        end
      end, 100)
    end,
  })
end

-- Create the :IDE command
vim.api.nvim_create_user_command("IDE", M.setup_ide_layout, {})

return M
