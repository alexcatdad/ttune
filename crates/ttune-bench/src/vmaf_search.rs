use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct VmafSearchResult {
    pub codec: String,
    pub target_vmaf: f32,
    pub quality_param: String,
    pub note: String,
}

pub fn search(codec: &str, target_vmaf: f32) -> VmafSearchResult {
    let quality_param = match codec {
        "av1" => "-crf 32",
        "h264" => "-crf 20",
        _ => "-crf 22",
    }
    .to_string();

    VmafSearchResult {
        codec: codec.to_string(),
        target_vmaf,
        quality_param,
        note: "Heuristic fallback result; wire ffmpeg/libvmaf loop for full search".to_string(),
    }
}
