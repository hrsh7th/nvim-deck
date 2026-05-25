local M = {}

---@param git deck.x.Git
---@param branch_name string
---@return string
function M.get_default_worktree_path(git, branch_name)
  local repo_root = vim.fs.normalize(vim.fs.dirname(git:get_common_git_dir()))
  local safe_name = branch_name:gsub('[/\\]', '-')
  return vim.fs.joinpath(vim.fs.dirname(repo_root), ('%s-%s'):format(vim.fs.basename(repo_root), safe_name))
end

return M
