use clap::{Parser, Subcommand};

mod vmaf_search;

#[derive(Parser)]
#[command(name = "ttune-bench")]
#[command(about = "Optional Transcode Tuner benchmark accelerator")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    VmafSearch {
        #[arg(long)]
        input: String,
        #[arg(long, default_value = "hevc")]
        codec: String,
        #[arg(long, default_value_t = 95.0)]
        target_vmaf: f32,
        #[arg(long)]
        json: bool,
    },
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Commands::VmafSearch {
            input: _,
            codec,
            target_vmaf,
            json,
        } => {
            let result = vmaf_search::search(&codec, target_vmaf);
            if json {
                println!("{}", serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()));
            } else {
                println!(
                    "codec={} target_vmaf={} quality_param={}",
                    result.codec, result.target_vmaf, result.quality_param
                );
            }
        }
    }
}
