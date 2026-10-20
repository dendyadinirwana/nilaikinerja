mod validator;

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tauri::{AppHandle, Manager, LogicalPosition, LogicalSize, Position, Size, Window};
use validator::{validate_file, ValidationResult};

fn get_app_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("Gagal mendapatkan app data dir: {}", e))?;
    fs::create_dir_all(&dir).map_err(|e| format!("Gagal membuat direktori data: {}", e))?;
    Ok(dir)
}

#[tauri::command]
fn validate_dropped_file(path: String) -> ValidationResult {
    validate_file(&path)
}

#[tauri::command]
fn reveal_in_explorer(path: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        Command::new("explorer")
            .args(["/select,", &path])
            .spawn()
            .map_err(|e| format!("Gagal membuka Windows Explorer: {}", e))?;
    }

    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .args(["-R", &path])
            .spawn()
            .map_err(|e| format!("Gagal membuka Finder: {}", e))?;
    }

    #[cfg(target_os = "linux")]
    {
        if let Some(parent) = std::path::Path::new(&path).parent() {
            Command::new("xdg-open")
                .arg(parent)
                .spawn()
                .map_err(|e| format!("Gagal membuka File Manager: {}", e))?;
        }
    }

    Ok(())
}

#[tauri::command]
fn set_window_mode(window: Window, mode: String) -> Result<(), String> {
    let (target_w, target_h) = match mode.as_str() {
        "idle" => (320.0, 48.0),
        "hover" => (420.0, 56.0),
        "expanded" => (680.0, 640.0),
        _ => (680.0, 640.0),
    };

    let _ = window.set_size(Size::Logical(LogicalSize {
        width: target_w,
        height: target_h,
    }));

    if let Ok(Some(monitor)) = window.current_monitor() {
        let scale = monitor.scale_factor();
        let mon_width_logical = monitor.size().width as f64 / scale;
        let x_pos = (mon_width_logical - target_w) / 2.0;

        let _ = window.set_position(Position::Logical(LogicalPosition {
            x: x_pos.max(0.0),
            y: 0.0,
        }));
    }

    Ok(())
}

#[tauri::command]
fn load_persisted_data(app: AppHandle) -> Result<String, String> {
    let app_dir = get_app_dir(&app)?;
    let file_path = app_dir.join("data.json");
    if !file_path.exists() {
        return Ok("{}".into());
    }
    fs::read_to_string(file_path).map_err(|e| format!("Gagal membaca data: {}", e))
}

#[tauri::command]
fn save_persisted_data(app: AppHandle, json_content: String) -> Result<(), String> {
    let app_dir = get_app_dir(&app)?;
    let file_path = app_dir.join("data.json");
    fs::write(file_path, json_content).map_err(|e| format!("Gagal menyimpan data: {}", e))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            validate_dropped_file,
            reveal_in_explorer,
            set_window_mode,
            load_persisted_data,
            save_persisted_data
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
