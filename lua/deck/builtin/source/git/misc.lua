local M = {}

---@param cwd string
---@param branch_name string
---@return string
function M.get_default_worktree_path(cwd, branch_name)
  local safe_name = branch_name:gsub('[/\\]', '-')
  return vim.fs.joinpath(vim.fs.dirname(cwd), ('%s-%s'):format(vim.fs.basename(cwd), safe_name))
end

return M
