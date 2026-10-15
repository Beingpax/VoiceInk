//! RAII helpers for GDI painting, shared by the overlay and the dashboard.
//!
//! Every created object is deleted and every selection undone on drop, so
//! paint code cannot leak handles on early returns.

use windows::Win32::Foundation::{COLORREF, HWND, RECT};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, BitBlt, CLEARTYPE_QUALITY, CLIP_DEFAULT_PRECIS, CreateCompatibleBitmap, CreateCompatibleDC,
    CreateFontW, CreateSolidBrush, DEFAULT_CHARSET, DRAW_TEXT_FORMAT, DeleteDC, DeleteObject, DrawTextW, EndPaint,
    FONT_WEIGHT, FillRect, GetStockObject, HBRUSH, HDC, HFONT, HGDIOBJ, NULL_PEN, OUT_DEFAULT_PRECIS, PAINTSTRUCT,
    RoundRect, SRCCOPY, SelectObject, SetBkMode, SetTextColor, TRANSPARENT,
};
use windows::Win32::UI::WindowsAndMessaging::GetClientRect;
use windows::core::w;

pub const fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
    COLORREF(r as u32 | (g as u32) << 8 | (b as u32) << 16)
}

/// A GDI object (brush, font, bitmap, region) deleted on drop.
pub struct Owned(HGDIOBJ);

impl Owned {
    pub fn raw(&self) -> HGDIOBJ {
        self.0
    }
}

impl Drop for Owned {
    fn drop(&mut self) {
        // SAFETY: the object was created by this module and is no longer selected.
        let _ = unsafe { DeleteObject(self.0) };
    }
}

pub fn solid_brush(color: COLORREF) -> Owned {
    // SAFETY: no preconditions.
    Owned(HGDIOBJ(unsafe { CreateSolidBrush(color) }.0))
}

/// A Segoe UI font of `height_px` pixels.
pub fn font(height_px: i32, weight: FONT_WEIGHT) -> Owned {
    // SAFETY: the face name is a static NUL-terminated string.
    let font = unsafe {
        CreateFontW(
            -height_px,
            0,
            0,
            0,
            weight.0.cast_signed(),
            0,
            0,
            0,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            0,
            w!("Segoe UI"),
        )
    };
    Owned(HGDIOBJ(font.0))
}

impl From<&Owned> for HFONT {
    fn from(o: &Owned) -> Self {
        HFONT(o.0.0)
    }
}

/// Selects an object into a DC and restores the previous one on drop.
pub struct Selection {
    dc: HDC,
    previous: HGDIOBJ,
}

impl Selection {
    pub fn new(dc: HDC, object: HGDIOBJ) -> Self {
        // SAFETY: `dc` is a live device context and `object` a live GDI object.
        Self { dc, previous: unsafe { SelectObject(dc, object) } }
    }
}

impl Drop for Selection {
    fn drop(&mut self) {
        // SAFETY: restores the object that was selected before.
        unsafe { SelectObject(self.dc, self.previous) };
    }
}

/// Double-buffered painting for `WM_PAINT`: draw into [`BufferedPaint::dc`],
/// the result is copied to the window on drop.
pub struct BufferedPaint {
    hwnd: HWND,
    paint: PAINTSTRUCT,
    window_dc: HDC,
    dc: HDC,
    #[allow(dead_code)] // kept alive until the buffer is copied in Drop
    bitmap: Owned,
    selection: Option<Selection>,
    pub rect: RECT,
}

impl BufferedPaint {
    pub fn begin(hwnd: HWND) -> Self {
        let mut paint = PAINTSTRUCT::default();
        let mut rect = RECT::default();
        // SAFETY: called from WM_PAINT of `hwnd`; matched by EndPaint in Drop.
        unsafe {
            let window_dc = BeginPaint(hwnd, &raw mut paint);
            let _ = GetClientRect(hwnd, &raw mut rect);
            let dc = CreateCompatibleDC(Some(window_dc));
            let bitmap = Owned(HGDIOBJ(CreateCompatibleBitmap(window_dc, rect.right, rect.bottom).0));
            let selection = Selection::new(dc, bitmap.raw());
            Self { hwnd, paint, window_dc, dc, bitmap, selection: Some(selection), rect }
        }
    }

    pub fn fill(&self, rect: &RECT, brush: HBRUSH) {
        // SAFETY: valid DC, rect and brush.
        unsafe { FillRect(self.dc, rect, brush) };
    }

    /// Filled rounded rectangle without outline.
    pub fn round_rect(&self, rect: RECT, radius: i32, color: COLORREF) {
        let brush = solid_brush(color);
        let _brush = Selection::new(self.dc, brush.raw());
        // SAFETY: the stock pen needs no cleanup.
        let _pen = Selection::new(self.dc, unsafe { GetStockObject(NULL_PEN) });
        // SAFETY: valid DC with brush and pen selected.
        let _ = unsafe { RoundRect(self.dc, rect.left, rect.top, rect.right + 1, rect.bottom + 1, radius, radius) };
    }

    pub fn text(&self, text: &str, rect: RECT, font: &Owned, color: COLORREF, format: DRAW_TEXT_FORMAT) {
        let mut rect = rect;
        let mut units: Vec<u16> = text.encode_utf16().collect();
        let _font = Selection::new(self.dc, font.raw());
        // SAFETY: valid DC; DrawTextW reads `units` and may adjust `rect`.
        unsafe {
            SetBkMode(self.dc, TRANSPARENT);
            SetTextColor(self.dc, color);
            DrawTextW(self.dc, &mut units, &raw mut rect, format);
        }
    }
}

impl Drop for BufferedPaint {
    fn drop(&mut self) {
        let (w, h) = (self.rect.right, self.rect.bottom);
        // SAFETY: copies the finished buffer, then releases everything in
        // reverse order of creation; EndPaint matches BeginPaint.
        unsafe {
            let _ = BitBlt(self.window_dc, 0, 0, w, h, Some(self.dc), 0, 0, SRCCOPY);
            self.selection = None; // deselect the bitmap; it is deleted after this body
            let _ = DeleteDC(self.dc);
            let _ = EndPaint(self.hwnd, &raw const self.paint);
        }
    }
}
