return {
  "akinsho/toggleterm.nvim",
  version = "*",
  config = function()
    require("toggleterm").setup({
      size = 20,
      open_mapping = [[<c-\>]],
      hide_numbers = true,
      shade_terminals = true,
      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      direction = "float",
      close_on_exit = true,
      shell = vim.o.shell,
      float_opts = {
        border = "curved",
        winblend = 0,
      },
    })

    local Terminal = require("toggleterm.terminal").Terminal

    -- Track current terminal index
    local term_idx = 1
    local terminals = {}

    -- Function to get or create terminal
    local function get_terminal(idx)
      if not terminals[idx] then
        terminals[idx] = Terminal:new({
          count = idx,
          direction = "float",
          on_close = function()
            terminals[idx] = nil
          end,
        })
      end
      return terminals[idx]
    end

    -- Toggle current terminal
    vim.keymap.set("n", "<leader>t", function()
      get_terminal(term_idx):toggle()
    end, { desc = "Toggle terminal" })

    -- Create new terminal (next tab)
    vim.keymap.set("n", "<leader>tn", function()
      term_idx = term_idx + 1
      get_terminal(term_idx):toggle()
    end, { desc = "New terminal tab" })

    -- Cycle to next terminal
    vim.keymap.set("n", "<leader>]", function()
      get_terminal(term_idx):close()
      term_idx = term_idx % 10 + 1
      get_terminal(term_idx):open()
    end, { desc = "Next terminal" })

    -- Cycle to previous terminal
    vim.keymap.set("n", "<leader>[", function()
      get_terminal(term_idx):close()
      term_idx = term_idx - 1
      if term_idx < 1 then term_idx = 10 end
      get_terminal(term_idx):open()
    end, { desc = "Previous terminal" })

    -- Close current terminal
    vim.keymap.set("n", "<leader>tc", function()
      get_terminal(term_idx):shutdown()
      terminals[term_idx] = nil
    end, { desc = "Close terminal" })

    -- Exit terminal mode
    vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

    -- Pass C-c to terminal
    vim.keymap.set("t", "<C-c>", "<C-c>", { desc = "Send C-c to terminal" })
  end,
}
