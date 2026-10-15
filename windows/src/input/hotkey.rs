//! Hotkey specifications such as `RightCtrl`, `F9`, `Ctrl+Shift+Space` or
//! `Mouse4`, parsed into Windows virtual-key codes.

/// Virtual-key codes used by the parser (values from `WinUser.h`).
pub mod vk {
    pub const BACK: u16 = 0x08;
    pub const TAB: u16 = 0x09;
    pub const RETURN: u16 = 0x0D;
    pub const SHIFT: u16 = 0x10;
    pub const CONTROL: u16 = 0x11;
    pub const MENU: u16 = 0x12;
    pub const PAUSE: u16 = 0x13;
    pub const CAPITAL: u16 = 0x14;
    pub const ESCAPE: u16 = 0x1B;
    pub const SPACE: u16 = 0x20;
    pub const PRIOR: u16 = 0x21;
    pub const NEXT: u16 = 0x22;
    pub const END: u16 = 0x23;
    pub const HOME: u16 = 0x24;
    pub const LEFT: u16 = 0x25;
    pub const UP: u16 = 0x26;
    pub const RIGHT: u16 = 0x27;
    pub const DOWN: u16 = 0x28;
    pub const SNAPSHOT: u16 = 0x2C;
    pub const INSERT: u16 = 0x2D;
    pub const DELETE: u16 = 0x2E;
    pub const LWIN: u16 = 0x5B;
    pub const RWIN: u16 = 0x5C;
    pub const APPS: u16 = 0x5D;
    pub const F1: u16 = 0x70;
    pub const SCROLL: u16 = 0x91;
    pub const LSHIFT: u16 = 0xA0;
    pub const RSHIFT: u16 = 0xA1;
    pub const LCONTROL: u16 = 0xA2;
    pub const RCONTROL: u16 = 0xA3;
    pub const LMENU: u16 = 0xA4;
    pub const RMENU: u16 = 0xA5;
    pub const XBUTTON1: u16 = 0x05;
    pub const XBUTTON2: u16 = 0x06;
    pub const MBUTTON: u16 = 0x04;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Modifiers {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub win: bool,
}

impl Modifiers {
    pub fn is_empty(&self) -> bool {
        !(self.ctrl || self.alt || self.shift || self.win)
    }
}

/// A parsed hotkey.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hotkey {
    /// A modifier pressed and released on its own, e.g. `RightCtrl`.
    ModifierOnly { vk: u16 },
    /// A regular key with optional modifiers, e.g. `Ctrl+Shift+Space` or `F9`.
    Key { vk: u16, modifiers: Modifiers },
    /// A mouse button (`Mouse4`, `Mouse5`, `MiddleMouse`).
    Mouse { button: u16 },
}

pub fn is_modifier_vk(code: u16) -> bool {
    matches!(
        code,
        vk::SHIFT
            | vk::CONTROL
            | vk::MENU
            | vk::LSHIFT
            | vk::RSHIFT
            | vk::LCONTROL
            | vk::RCONTROL
            | vk::LMENU
            | vk::RMENU
            | vk::LWIN
            | vk::RWIN
    )
}

fn key_name_to_vk(name: &str) -> Option<u16> {
    let n = name.trim().to_ascii_lowercase().replace([' ', '_', '-'], "");
    let code = match n.as_str() {
        "ctrl" | "control" => vk::CONTROL,
        "shift" => vk::SHIFT,
        "alt" => vk::MENU,
        "rightctrl" | "rctrl" | "rightcontrol" => vk::RCONTROL,
        "leftctrl" | "lctrl" | "leftcontrol" => vk::LCONTROL,
        "rightalt" | "ralt" | "altgr" => vk::RMENU,
        "leftalt" | "lalt" => vk::LMENU,
        "rightshift" | "rshift" => vk::RSHIFT,
        "leftshift" | "lshift" => vk::LSHIFT,
        "rightwin" | "rwin" => vk::RWIN,
        "leftwin" | "lwin" => vk::LWIN,
        "space" => vk::SPACE,
        "enter" | "return" => vk::RETURN,
        "tab" => vk::TAB,
        "esc" | "escape" => vk::ESCAPE,
        "backspace" => vk::BACK,
        "pause" | "break" => vk::PAUSE,
        "capslock" => vk::CAPITAL,
        "scrolllock" => vk::SCROLL,
        "printscreen" | "prtsc" => vk::SNAPSHOT,
        "insert" | "ins" => vk::INSERT,
        "delete" | "del" => vk::DELETE,
        "home" => vk::HOME,
        "end" => vk::END,
        "pageup" | "pgup" => vk::PRIOR,
        "pagedown" | "pgdn" => vk::NEXT,
        "left" => vk::LEFT,
        "right" => vk::RIGHT,
        "up" => vk::UP,
        "down" => vk::DOWN,
        "menu" | "apps" => vk::APPS,
        "`" | "backtick" | "grave" => 0xC0,
        "," | "comma" => 0xBC,
        "." | "period" => 0xBE,
        "/" | "slash" => 0xBF,
        ";" | "semicolon" => 0xBA,
        _ => {
            if let Some(num) = n.strip_prefix('f').and_then(|d| d.parse::<u16>().ok()) {
                if (1..=24).contains(&num) {
                    return Some(vk::F1 + num - 1);
                }
                return None;
            }
            let mut chars = n.chars();
            match (chars.next(), chars.next()) {
                (Some(c), None) if c.is_ascii_alphanumeric() => u16::from(u8::try_from(c.to_ascii_uppercase()).ok()?),
                _ => return None,
            }
        }
    };
    Some(code)
}

fn mouse_name(name: &str) -> Option<u16> {
    match name.trim().to_ascii_lowercase().replace([' ', '_', '-'], "").as_str() {
        "mouse4" | "xbutton1" | "mouseback" => Some(vk::XBUTTON1),
        "mouse5" | "xbutton2" | "mouseforward" => Some(vk::XBUTTON2),
        "middlemouse" | "mouse3" | "mbutton" => Some(vk::MBUTTON),
        _ => None,
    }
}

/// Why a hotkey specification could not be parsed.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HotkeyError {
    #[error("the shortcut is empty")]
    Empty,
    #[error("unknown key '{0}'")]
    UnknownKey(String),
    #[error("unknown modifier '{0}'")]
    UnknownModifier(String),
    #[error("the last part of a key combination must be a non-modifier key")]
    ModifierAsKey,
}

impl std::str::FromStr for Hotkey {
    type Err = HotkeyError;

    fn from_str(spec: &str) -> Result<Self, Self::Err> {
        let parts: Vec<&str> = spec.split('+').map(str::trim).filter(|p| !p.is_empty()).collect();
        let Some((&last, modifier_names)) = parts.split_last() else {
            return Err(HotkeyError::Empty);
        };
        if modifier_names.is_empty()
            && let Some(button) = mouse_name(last)
        {
            return Ok(Hotkey::Mouse { button });
        }

        let code = key_name_to_vk(last).ok_or_else(|| HotkeyError::UnknownKey(last.to_string()))?;
        if modifier_names.is_empty() && is_modifier_vk(code) {
            return Ok(Hotkey::ModifierOnly { vk: code });
        }
        if is_modifier_vk(code) {
            return Err(HotkeyError::ModifierAsKey);
        }

        let mut modifiers = Modifiers::default();
        for name in modifier_names {
            match name.to_ascii_lowercase().as_str() {
                "ctrl" | "control" => modifiers.ctrl = true,
                "alt" => modifiers.alt = true,
                "shift" => modifiers.shift = true,
                "win" | "super" | "meta" => modifiers.win = true,
                other => return Err(HotkeyError::UnknownModifier(other.to_string())),
            }
        }
        Ok(Hotkey::Key { vk: code, modifiers })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(spec: &str) -> Result<Hotkey, HotkeyError> {
        spec.parse()
    }

    #[test]
    fn parses_modifier_only_keys() {
        assert_eq!(parse("RightCtrl"), Ok(Hotkey::ModifierOnly { vk: vk::RCONTROL }));
        assert_eq!(parse("altgr"), Ok(Hotkey::ModifierOnly { vk: vk::RMENU }));
        assert_eq!(parse("Shift"), Ok(Hotkey::ModifierOnly { vk: vk::SHIFT }));
    }

    #[test]
    fn parses_keys_and_combinations() {
        assert_eq!(parse("F9"), Ok(Hotkey::Key { vk: 0x78, modifiers: Modifiers::default() }));
        assert_eq!(
            parse("Ctrl+Shift+Space"),
            Ok(Hotkey::Key { vk: vk::SPACE, modifiers: Modifiers { ctrl: true, shift: true, ..Modifiers::default() } })
        );
        assert_eq!(
            parse("alt+q"),
            Ok(Hotkey::Key { vk: u16::from(b'Q'), modifiers: Modifiers { alt: true, ..Modifiers::default() } })
        );
    }

    #[test]
    fn parses_mouse_buttons() {
        assert_eq!(parse("Mouse4"), Ok(Hotkey::Mouse { button: vk::XBUTTON1 }));
    }

    #[test]
    fn rejects_invalid_specs() {
        assert_eq!(parse(" + "), Err(HotkeyError::Empty));
        assert_eq!(parse("Ctrl+Shift"), Err(HotkeyError::ModifierAsKey));
        assert_eq!(parse("Hyper+K"), Err(HotkeyError::UnknownModifier("hyper".into())));
        assert_eq!(parse("F25"), Err(HotkeyError::UnknownKey("F25".into())));
        assert!(parse("Ctrl+Mouse4").is_err());
    }
}
