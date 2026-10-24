(() => {
  if (!/(^|\.)soundcloud\.com$/.test(location.hostname)) return;

  const post = (message) => window.webkit.messageHandlers.player.postMessage(message);

  const media = new Set();
  // Set when the Mac goes to sleep; any playback that starts before the user
  // interacts again is treated as unwanted and paused.
  let suspended = false;
  // When the Mac wakes up, WebKit resumes media interrupted by sleep by sending
  // a "play" action of its own, which must not be mistaken for the user's.
  let sleeping = false;
  let wokeAt = 0;
  const isWakingUp = () => sleeping || Date.now() - wokeAt < 1500;

  const playButton = () => document.querySelector(".playControls__play");
  const isPlaying = () => {
    const button = playButton();
    if (button) return button.classList.contains("playing");
    return [...media].some((element) => !element.paused);
  };

  const togglePlayback = () => playButton()?.click();

  const pause = () => {
    if (playButton()?.classList.contains("playing")) togglePlayback();
    media.forEach((element) => element.pause());
  };

  // The element SoundCloud is playing through, or the last one it used.
  let current = null;

  const metadata = () => {
    const data = navigator.mediaSession?.metadata;
    if (!data?.title) return null;
    const artwork = [...(data.artwork ?? [])].pop()?.src ?? "";
    return { title: data.title, artist: data.artist ?? "", album: data.album ?? "", artwork };
  };

  // The app keeps its own Now Playing entry. WebKit's own one lives in its
  // GPU process, whose bundle id every web view on the Mac shares, so other
  // apps cannot address it while another player is the current one.
  const report = () => {
    const playing = [...media].some((element) => !element.paused && !element.ended);
    const track = metadata();
    const duration = current && Number.isFinite(current.duration) ? current.duration : 0;
    const position = current ? current.currentTime : 0;
    post({ playing, track: track ? { ...track, duration, position } : null });
  };

  const resume = () => { suspended = false; };
  window.addEventListener("pointerdown", resume, true);
  window.addEventListener("keydown", resume, true);

  window.desktopPlayer = {
    suspend() {
      suspended = true;
      sleeping = true;
      pause();
    },
    wake() {
      sleeping = false;
      wokeAt = Date.now();
    },
    command(action, value) {
      if (action === "toggle") {
        (isPlaying() ? handlers.pause : handlers.play)();
      } else if (action === "seekto") {
        if (pageHandlers.seekto) pageHandlers.seekto({ action, seekTime: value });
        else if (current) current.currentTime = value;
      } else {
        handlers[action]?.();
      }
    },
  };

  // Control Center and the keyboard media keys go through the Media Session API.
  // SoundCloud only registers play/pause there, so macOS falls back to +/-15s skip buttons.
  const session = navigator.mediaSession;

  const handlers = {
    play: () => {
      if (suspended && isWakingUp()) return;
      resume();
      if (!isPlaying()) togglePlayback();
    },
    pause: () => {
      if (isPlaying()) togglePlayback();
    },
    previoustrack: () => document.querySelector(".skipControl__previous")?.click(),
    nexttrack: () => document.querySelector(".skipControl__next")?.click(),
    seekbackward: null,
    seekforward: null,
  };

  const setActionHandler = session?.setActionHandler.bind(session);
  // What the page registers for actions left to it, kept for the app's own
  // controls: seeking goes through SoundCloud so its progress bar follows.
  const pageHandlers = {};

  // WebKit drops registered commands while no media element exists,
  // so they have to be registered again once playback starts.
  const registerHandlers = () => {
    if (!setActionHandler) return;
    for (const [action, handler] of Object.entries(handlers)) {
      try {
        setActionHandler(action, handler);
      } catch {}
    }
  };

  if (session) {
    session.setActionHandler = (action, handler) => {
      if (action in handlers) return;
      pageHandlers[action] = handler;
      setActionHandler(action, handler);
    };
    registerHandlers();

    // A new track arrives as new metadata, before or after its audio starts.
    const property = Object.getOwnPropertyDescriptor(MediaSession.prototype, "metadata");
    if (property?.get && property.set) {
      Object.defineProperty(session, "metadata", {
        configurable: true,
        get() { return property.get.call(this); },
        set(value) {
          property.set.call(this, value);
          report();
        },
      });
    }
  }

  const track = (element) => {
    if (media.has(element)) return;
    media.add(element);
    element.addEventListener("playing", () => {
      current = element;
      if (suspended) pause();
      registerHandlers();
      report();
    });
    for (const name of ["pause", "ended", "seeked", "durationchange"]) {
      element.addEventListener(name, () => {
        if (element === current) report();
      });
    }
  };

  // The window title bar takes the color of SoundCloud's header.
  let pageColor = "";
  const reportPageColor = () => {
    const header = document.querySelector("header.header");
    if (!header) return false;
    const [r, g, b, a = 1] = getComputedStyle(header).backgroundColor.match(/[\d.]+/g)?.map(Number) ?? [];
    if (r === undefined || a === 0) return false;
    const color = `${r},${g},${b}`;
    if (color !== pageColor) {
      pageColor = color;
      post({ color: [r, g, b] });
    }
    return true;
  };

  // Wait for the header to render, then only follow theme switches on <body>.
  const pageObserver = new MutationObserver(() => {
    if (!reportPageColor()) return;
    pageObserver.disconnect();
    new MutationObserver(reportPageColor).observe(document.body, { attributes: true, attributeFilter: ["class"] });
  });
  pageObserver.observe(document, { childList: true, subtree: true });

  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    track(this);
    return originalPlay.apply(this, args);
  };

  document.addEventListener("play", (event) => {
    if (event.target instanceof HTMLMediaElement) track(event.target);
  }, true);
})();
