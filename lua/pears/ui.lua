local Utils = require "pears.utils"
local Common = require "pears.common"
local api = vim.api

local M = {}

M._highlight_timer_count = 0

function M.highlight_pair_results(bufnr, results, timeout)
  for _, pear in Utils.to_iter(results) do
    if pear then
      api.nvim_buf_set_extmark(bufnr, Common.Ns.Highlight, pear.start_range[1], pear.start_range[2], {
        hl_group = Common.Hl.Pairs,
        end_line = pear.start_range[3],
        end_col = pear.start_range[4] + 1
      })
      api.nvim_buf_set_extmark(bufnr, Common.Ns.Highlight, pear.end_range[1], pear.end_range[2], {
        hl_group = Common.Hl.Pairs,
        end_line = pear.end_range[3],
        end_col = pear.end_range[4] + 1
      })
    end
  end

  if Utils.is_number(timeout) then
    Utils.set_timeout(vim.schedule_wrap(function()
      M._highlight_timer_count = M._highlight_timer_count - 1

      if M._highlight_timer_count < 1 then
        M.clear_pair_highlights(bufnr)
      end
    end), timeout)
  end
end

function M.clear_pair_highlights(bufnr)
  api.nvim_buf_clear_namespace(bufnr, Common.Ns.Highlight, 0, -1)
end

return M
