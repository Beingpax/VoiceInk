//! User actions offered both by the tray menu and the settings window.

use super::open_path;
use crate::context::AppContext;

/// Exports the history to `history.csv` in the data folder and opens it.
///
/// # Errors
/// Returns the I/O error when the file cannot be written.
pub fn open_history_csv(ctx: &AppContext) -> std::io::Result<()> {
    let out = ctx.paths.history_csv();
    ctx.history.export_csv_file(&out)?;
    open_path(&out);
    Ok(())
}

pub fn open_data_folder(ctx: &AppContext) {
    open_path(ctx.paths.root());
}

/// Opens `config.json` (e.g. to edit modes, which have no UI yet).
pub fn open_config_file(ctx: &AppContext) {
    open_path(&ctx.paths.config());
}
