// 清理本工具做无头截图时可能残留的浏览器进程与 profile 目录。
// 只处理命令行里带 tmp_bprof_ / tmp_edgeprof_ 标记的 chrome/msedge，
// 不会碰用户自己开着的浏览器。
// 用法: node tools/npk_inspector/test/cleanup.mjs
import { spawnSync } from 'node:child_process';

const PS = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
const script = `
$p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  ($_.Name -eq 'chrome.exe' -or $_.Name -eq 'msedge.exe') -and $_.CommandLine -and
  ($_.CommandLine -match 'tmp_bprof_|tmp_edgeprof_')
}
$n = @($p).Count
$p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-ChildItem 'E:\\' -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like 'tmp_bprof_*' -or $_.Name -like 'tmp_edgeprof_*' } |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ("killed=" + $n)
`;
const r = spawnSync(PS, ['-NoProfile', '-Command', script], { encoding: 'utf8', timeout: 60000 });
console.log((r.stdout || '').trim() || (r.stderr || '').trim() || '完成');
