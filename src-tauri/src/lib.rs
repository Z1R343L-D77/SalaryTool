//! 应用入口。
//!
//! 计算逻辑全部在前端 `src/core` 中实现（纯函数、可单测）。
//! Rust 侧只处理桌面环境特有的能力：把备份数据写到用户选定（或默认）的位置。

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
        "salarytool-backup.json".to_string()
    } else {
        trimmed
    }
}

/// 把前端导出的 JSON 写入用户指定路径；不传路径时退回下载目录。
#[tauri::command]
fn save_backup(
    app: tauri::AppHandle,
    contents: String,
    path: Option<String>,
) -> Result<String, String> {
    let target: PathBuf = match path.filter(|p| !p.trim().is_empty()) {
        Some(chosen) => {
            let mut buf = PathBuf::from(chosen.trim());
            // 用户在保存对话框里没写扩展名时补上
            if buf.extension().is_none() {
                buf.set_extension("json");
            }
            buf
        }
        None => {
            let dir: PathBuf = app
                .path()
                .download_dir()
                .or_else(|_| app.path().document_dir())
                .map_err(|e| format!("找不到可写入的目录：{e}"))?;
            fs::create_dir_all(&dir).map_err(|e| format!("创建目录失败：{e}"))?;
            unique_target(dir, "salarytool-backup.json")
        }
    };

    if let Some(parent) = target.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("创建目录失败：{e}"))?;
        }
    }

    fs::write(&target, contents).map_err(|e| format!("写入文件失败：{e}"))?;
    Ok(target.to_string_lossy().to_string())
}

/// 同名文件不覆盖，自动加序号。
fn unique_target(dir: PathBuf, file_name: &str) -> PathBuf {
    let target = dir.join(sanitize_file_name(file_name));
    if !target.exists() {
        return target;
    }
    let stem = target
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "salarytool-backup".to_string());
    let ext = target
        .extension()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "json".to_string());
    let mut index = 2;
    loop {
        let candidate = dir.join(format!("{stem}-{index}.{ext}"));
        if !candidate.exists() {
            return candidate;
        }
        index += 1;
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![app_version, save_backup])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{sanitize_file_name, unique_target};
    use std::fs;

    #[test]
    fn keeps_normal_names() {
        assert_eq!(sanitize_file_name("salarytool-backup.json"), "salarytool-backup.json");
    }

    #[test]
    fn strips_path_separators() {
        // 分隔符被替换，且开头的点会被去掉，避免生成隐藏文件或 `..` 前缀
        assert_eq!(sanitize_file_name("../../evil.json"), "_.._evil.json");
        assert_eq!(sanitize_file_name("a/b\\c.json"), "a_b_c.json");
    }

    #[test]
    fn falls_back_when_empty() {
        assert_eq!(sanitize_file_name("   "), "salarytool-backup.json");
        assert_eq!(sanitize_file_name("..."), "salarytool-backup.json");
    }

    #[test]
    fn unique_target_avoids_overwrite() {
        let dir = std::env::temp_dir().join("salarytool-test-unique");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let first = unique_target(dir.clone(), "backup.json");
        assert_eq!(first.file_name().unwrap(), "backup.json");

        fs::write(&first, "{}").unwrap();
        let second = unique_target(dir.clone(), "backup.json");
        assert_eq!(second.file_name().unwrap(), "backup-2.json");

        fs::write(&second, "{}").unwrap();
        let third = unique_target(dir.clone(), "backup.json");
        assert_eq!(third.file_name().unwrap(), "backup-3.json");

        let _ = fs::remove_dir_all(&dir);
    }
}
