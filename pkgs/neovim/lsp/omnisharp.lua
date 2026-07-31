-- OmniSharp (omnisharp-roslyn) — C# language server.
--
-- Chosen because this is a .NET Framework 4.5.2/4.6.1 (non-SDK-style)
-- project built with mono via `msbuild` (see shell.nix/.envrc in the repo).
--
-- IMPORTANT: this build of omnisharp-roslyn is a self-contained .NET 8
-- (CoreCLR) executable, not a mono build — it does NOT drive MSBuild through
-- mono, and it cannot load mono's MSBuild assemblies in-process (different
-- runtimes). It uses Microsoft.Build.Locator to find a dotnet-SDK MSBuild
-- instead. That MSBuild has no mono-specific fallback for resolving full
-- Framework reference assemblies (System.dll etc.), so without help every
-- file fails with "The type or namespace name 'System' could not be found".
-- The fix is to hand it FrameworkPathOverride pointing at mono's own
-- reference-assembly facades for the highest TargetFrameworkVersion used in
-- the solution (currently v4.6.1), resolved from whichever `mono` is first
-- on PATH (the project's shell.nix puts the right one there via direnv).
local function mono_framework_path_override()
  local mono_bin = vim.fn.exepath('mono')
  if mono_bin == '' then
    return nil
  end
  local mono_root = vim.fn.fnamemodify(mono_bin, ':h:h')
  local override = mono_root .. '/lib/mono/4.6.1-api'
  if vim.fn.isdirectory(override) == 1 then
    return override
  end
  return nil
end

return {
  cmd = {
    'OmniSharp',
    '-z', -- pipe diagnostics as they are computed
    '--hostPID',
    tostring(vim.fn.getpid()),
    'DotNet:enablePackageRestore=false',
    '--encoding',
    'utf-8',
    '--languageserver',
  },
  filetypes = { 'cs', 'vb' },
  -- Prefer the nearest .sln/.csproj as the workspace root; fall back to
  -- an explicit omnisharp.json or the git root.
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local root = vim.fs.root(fname, function(name)
      return name:match('%.sln$') ~= nil or name:match('%.csproj$') ~= nil
    end) or vim.fs.root(fname, { 'omnisharp.json', '.git' })
    on_dir(root or vim.fs.dirname(fname))
  end,
  settings = {
    FormattingOptions = {
      -- Respect .editorconfig (formatting is handled by csharpier/conform).
      EnableEditorConfigSupport = true,
      OrganizeImports = true,
    },
    MsBuild = {
      -- Load all projects up front so cross-project navigation works.
      LoadProjectsOnDemand = false,
      Properties = (function()
        local override = mono_framework_path_override()
        if not override then
          return nil
        end
        return { FrameworkPathOverride = override }
      end)(),
    },
    RoslynExtensionsOptions = {
      EnableAnalyzersSupport = true,
      EnableImportCompletion = true,
      -- Analyze the whole solution, not just open files.
      AnalyzeOpenDocumentsOnly = false,
    },
    Sdk = {
      IncludePrereleases = true,
    },
  },
}
