//! The iced daemon: owns the event loop, opens the settings window on
//! request and forwards its results to the [`Host`].

use super::settings::{self, Outcome, SettingsWindow};
use super::{Desktop, Host, style};
use crate::artwork::{IconState, render_rgba};
use crate::context::AppContext;
use crate::settings_page::SettingsPage;
use iced::futures::channel::mpsc;
use iced::futures::{SinkExt, future};
use iced::widget::space;
use iced::{Element, Font, Size, Subscription, Task, Theme, window};
use std::rc::Rc;

const WINDOW_SIZE: Size = Size::new(1000.0, 700.0);
const MIN_WINDOW_SIZE: Size = Size::new(860.0, 560.0);
const ICON_EDGE: u32 = 64;
const REQUEST_BUFFER: usize = 32;

/// What the application asks the UI to do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UiRequest {
    /// Show the window on a page (or bring it forward).
    OpenSettings(SettingsPage),
    /// A dictation finished; refresh the dashboard.
    HistoryChanged,
    /// Leave the event loop.
    Quit,
}

/// Sends [`UiRequest`]s to the running UI from any thread.
#[derive(Clone)]
pub struct UiHandle(mpsc::Sender<Message>);

impl UiHandle {
    pub fn send(&self, request: UiRequest) {
        if let Err(e) = self.0.clone().try_send(Message::Request(request)) {
            log::warn!("UI request {request:?} dropped: {e}");
        }
    }
}

impl std::fmt::Debug for UiHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("UiHandle")
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    /// The request channel is ready.
    Connected(UiHandle),
    Request(UiRequest),
    Settings(window::Id, settings::Message),
    WindowClosed(window::Id),
}

struct Daemon {
    ctx: AppContext,
    desktop: Rc<dyn Desktop>,
    host: Rc<dyn Host>,
    settings: Option<(window::Id, SettingsWindow)>,
    /// Standalone settings window: quit when it closes.
    exit_on_close: bool,
}

impl Daemon {
    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Connected(handle) => {
                self.host.connected(handle);
                Task::none()
            }
            Message::Request(UiRequest::OpenSettings(page)) => self.open_settings(page),
            Message::Request(UiRequest::HistoryChanged) => {
                if let Some((_, window)) = &mut self.settings {
                    window.history_changed();
                }
                Task::none()
            }
            Message::Request(UiRequest::Quit) => {
                self.host.quit();
                iced::exit()
            }
            Message::Settings(id, message) => {
                let Some((_, window)) = self.settings.as_mut().filter(|(open, _)| *open == id) else {
                    return Task::none();
                };
                match window.update(message) {
                    Outcome::None => Task::none(),
                    Outcome::Saved => {
                        self.host.settings_saved();
                        Task::none()
                    }
                    Outcome::Close => window::close(id),
                }
            }
            Message::WindowClosed(id) => {
                if self.settings.as_ref().is_some_and(|(open, _)| *open == id) {
                    self.settings = None;
                }
                if self.exit_on_close { iced::exit() } else { Task::none() }
            }
        }
    }

    fn open_settings(&mut self, page: SettingsPage) -> Task<Message> {
        if let Some((id, window)) = &mut self.settings {
            window.show_page(page);
            return window::gain_focus(*id);
        }
        let window = match SettingsWindow::new(self.ctx.clone(), Rc::clone(&self.desktop), page) {
            Ok(window) => window,
            Err(e) => {
                log::error!("cannot open settings: {e}");
                return if self.exit_on_close { iced::exit() } else { Task::none() };
            }
        };
        let (id, open) = window::open(window_settings());
        self.settings = Some((id, window));
        open.discard()
    }

    fn view(&self, id: window::Id) -> Element<'_, Message> {
        match &self.settings {
            Some((open, window)) if *open == id => window.view().map(move |m| Message::Settings(id, m)),
            _ => space().into(),
        }
    }
}

fn window_settings() -> window::Settings {
    window::Settings {
        size: WINDOW_SIZE,
        min_size: Some(MIN_WINDOW_SIZE),
        position: window::Position::Centered,
        icon: window::icon::from_rgba(render_rgba(ICON_EDGE as usize, IconState::Idle), ICON_EDGE, ICON_EDGE).ok(),
        ..window::Settings::default()
    }
}

/// Hands a [`UiHandle`] to the update loop, then keeps the channel open.
fn requests() -> impl iced::futures::Stream<Item = Message> {
    iced::stream::channel(REQUEST_BUFFER, async |sender: mpsc::Sender<Message>| {
        let handle = UiHandle(sender.clone());
        let _ = sender.clone().send(Message::Connected(handle)).await;
        future::pending::<()>().await;
    })
}

fn subscription(_: &Daemon) -> Subscription<Message> {
    Subscription::batch([window::close_events().map(Message::WindowClosed), Subscription::run(requests)])
}

/// How [`run`] starts.
#[derive(Debug, Clone, Copy, Default)]
pub struct Launch {
    /// Open the settings window right away on this page.
    pub page: Option<SettingsPage>,
    /// Quit when the settings window closes (standalone mode).
    pub exit_on_close: bool,
}

/// Runs the UI event loop on the current thread until [`UiRequest::Quit`]
/// (or, with [`Launch::exit_on_close`], until the window closes).
///
/// # Errors
/// Fails when no window system or renderer is available.
pub fn run(ctx: AppContext, desktop: Rc<dyn Desktop>, host: Rc<dyn Host>, launch: Launch) -> iced::Result {
    let font = desktop.font_family().map_or(Font::DEFAULT, Font::with_name);
    style::set_font(font);
    let boot = move || {
        let mut daemon = Daemon {
            ctx: ctx.clone(),
            desktop: Rc::clone(&desktop),
            host: Rc::clone(&host),
            settings: None,
            exit_on_close: launch.exit_on_close,
        };
        let task = launch.page.map_or_else(Task::none, |page| daemon.open_settings(page));
        (daemon, task)
    };
    iced::daemon(boot, Daemon::update, Daemon::view)
        .title(|_: &Daemon, _| SettingsWindow::title().to_string())
        .theme(|_: &Daemon, _| -> Theme { style::theme() })
        .subscription(subscription)
        .default_font(font)
        .run()
}
