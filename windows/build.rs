//! Embeds the application manifest (Common Controls v6 visual styles,
//! per-monitor DPI awareness) into Windows builds.

fn main() {
    println!("cargo:rerun-if-changed=resources/voiceink.rc");
    println!("cargo:rerun-if-changed=resources/voiceink.manifest");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        // Optional so `cargo check` from non-Windows hosts without a resource compiler still works.
        if let Err(e) = embed_resource::compile("resources/voiceink.rc", embed_resource::NONE).manifest_optional() {
            println!("cargo:warning=application manifest not embedded: {e}");
        }
    }
}
