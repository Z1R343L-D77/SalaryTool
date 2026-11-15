//! iOS 端 Rust 侧。
//!
//! 计算逻辑全在 shared/ 的前端代码里，这里只提供两件事：
//!
//! 1. `app_version` —— 从 Cargo.toml 读版本号，界面右上角显示用。
//! 2. `save_state_file` / `load_state_file` —— 把工资数据写进 App 沙盒。
//!
//! 为什么需要文件持久化：
//! iOS 的 WKWebView 会在存储紧张时清理 localStorage，数据说没就没。
//! App 沙盒的 Application Support 目录受系统保护，不会被回收，
//! 所以主存储放在那里，localStorage 只作为首帧快速读取的缓存。

use std::fs;
use std::path::PathBuf;

use tauri::Manager;

#[tauri::command]
fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// 只保留文件名里安全的字符，避免路径穿越。
fn sanitize_file_name(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect();
    let trimmed = cleaned.trim().trim_start_matches('.').to_string();
    if trimmed.is_empty() {
        "salarytool-state.json".to_string()
    } else {
        trimmed
    }
}

/// App 内的数据目录：Application Support/salarytool。
///
/// 不用 Documents：那里会被 iCloud 备份、也会出现在「文件」App 里，
/// 工资数据没必要同步到云上。
fn data_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("找不到应用数据目录：{e}"))?;
    fs::create_dir_all(&base).map_err(|e| format!("创建目录失败：{e}"))?;
    Ok(base)
}

/// 写入一份状态文件（原子替换：先写临时文件再改名）。
#[tauri::command]
fn save_state_file(
    app: tauri::AppHandle,
    file_name: String,
    contents: String,
) -> Result<String, String> {
    let dir = data_dir(&app)?;
    let target = dir.join(sanitize_file_name(&file_name));
    let temp = target.with_extension("json.tmp");

    fs::write(&temp, contents).map_err(|e| format!("写入临时文件失败：{e}"))?;
    fs::rename(&temp, &target).map_err(|e| format!("替换文件失败：{e}"))?;
    Ok(target.to_string_lossy().to_string())
}

/// 读取状态文件；文件不存在时返回 None（而不是报错）。
#[tauri::command]
fn load_state_file(app: tauri::AppHandle, file_name: String) -> Result<Option<String>, String> {
    let dir = data_dir(&app)?;
    let target = dir.join(sanitize_file_name(&file_name));
    if !target.exists() {
        return Ok(None);
    }
    let text = fs::read_to_string(&target).map_err(|e| format!("读取文件失败：{e}"))?;
    Ok(Some(text))
}

/// 导出备份：写进沙盒的临时目录，返回路径，交给前端弹分享面板。
#[tauri::command]
fn save_export(
    app: tauri::AppHandle,
    file_name: String,
    contents: String,
) -> Result<String, String> {
    let dir = app
        .path()
        .app_cache_dir()
        .map_err(|e| format!("找不到缓存目录：{e}"))?;
    fs::create_dir_all(&dir).map_err(|e| format!("创建目录失败：{e}"))?;
    let target = dir.join(sanitize_file_name(&file_name));
    fs::write(&target, contents).map_err(|e| format!("写入文件失败：{e}"))?;
    Ok(target.to_string_lossy().to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            app_version,
            save_state_file,
            load_state_file,
            save_export
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::sanitize_file_name;

    #[test]
    fn keeps_normal_names() {
        assert_eq!(
            sanitize_file_name("salarytool-state.json"),
            "salarytool-state.json"
        );
    }

    #[test]
    fn strips_path_separators() {
        assert_eq!(sanitize_file_name("../../evil.json"), "_.._evil.json");
        assert_eq!(sanitize_file_name("a/b\\c.json"), "a_b_c.json");
    }

    #[test]
    fn falls_back_when_empty() {
        assert_eq!(sanitize_file_name("   "), "salarytool-state.json");
        assert_eq!(sanitize_file_name("..."), "salarytool-state.json");
    }
}
