// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pomodoro_app"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// ── DragBridge: lets users drag the frameless window via the title bar ──
const DragBridge = {
  mounted() {
    let startX = 0, startY = 0, dragging = false
    const self = this

    const titleBar = document.getElementById("title-bar")
    if (!titleBar) return

    titleBar.addEventListener("mousedown", (e) => {
      const region = getComputedStyle(e.target)["-webkit-app-region"]
      // Only drag on elements that are in the drag region and not controls
      if (e.target.closest("#btn-minimize, #btn-close")) return
      if (e.button !== 0) return
      dragging = true
      startX = e.screenX
      startY = e.screenY
      e.preventDefault()
    })

    window.addEventListener("mousemove", (e) => {
      if (!dragging) return
      const dx = e.screenX - startX
      const dy = e.screenY - startY
      if (Math.abs(dx) >= 1 || Math.abs(dy) >= 1) {
        self.pushEvent("window_drag", { dx, dy })
        startX = e.screenX
        startY = e.screenY
      }
    })

    window.addEventListener("mouseup", () => { dragging = false })
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: { ...colocatedHooks, DragBridge },
})

// ── Alarm Sound Player ──
// Plays gentle alarm sounds from priv/static/sounds/
// The server pushes {src: "/sounds/focus_end.mp3"} or similar
const alarmAudio = new Audio();
alarmAudio.volume = parseFloat(localStorage.getItem("pomo_alarm_volume") || "0.6");

window.addEventListener("phx:play_alarm", (e) => {
  const { src } = e.detail;
  if (src) {
    alarmAudio.src = src;
    alarmAudio.currentTime = 0;
    alarmAudio.play().catch(() => {
      console.warn("Alarm autoplay blocked — interact with the app to enable.");
    });
  }
});

window.addEventListener("phx:set_alarm_volume", (e) => {
  const { volume } = e.detail;
  if (volume !== undefined) {
    alarmAudio.volume = parseFloat(volume);
    localStorage.setItem("pomo_alarm_volume", volume.toString());
  }
});

window.addEventListener("phx:set_music_volume", (e) => {
  const { volume } = e.detail;
  if (volume !== undefined) {
    musicAudio.volume = parseFloat(volume);
    localStorage.setItem("pomo_music_volume", volume.toString());
  }
});

// Instant client-side volume response without waiting for network roundtrip
document.addEventListener("input", (e) => {
  if (e.target && (e.target.id === "music-volume-slider" || e.target.classList.contains("music-vol-slider"))) {
    const val = parseFloat(e.target.value);
    if (!isNaN(val)) {
      musicAudio.volume = Math.max(0, Math.min(1, val));
      localStorage.setItem("pomo_music_volume", val.toString());
    }
  }
});

// ── Music Player ──
// Separate audio element for background music (plays alongside alarm)
const musicAudio = new Audio();
musicAudio.volume = parseFloat(localStorage.getItem("pomo_music_volume") || "0.35");
musicAudio.loop = false;

// When a track ends naturally, tell the server to queue the next one
musicAudio.addEventListener("ended", () => {
  // Find the LiveView and push an event
  const lv = document.querySelector("[data-phx-session]");
  if (lv && window.liveSocket) {
    const view = window.liveSocket.getViewByEl(lv);
    if (view) {
      view.pushEvent("track_ended", {});
    }
  }
});

window.addEventListener("phx:music_play", (e) => {
  const { src } = e.detail;
  if (src) {
    // Only reload source if it changed
    try {
      const currentUrl = new URL(musicAudio.src || "http://localhost");
      const newUrl = new URL(src, window.location.origin);
      if (currentUrl.pathname !== newUrl.pathname) {
        musicAudio.src = src;
        musicAudio.currentTime = 0;
      }
    } catch {
      musicAudio.src = src;
      musicAudio.currentTime = 0;
    }
    musicAudio.volume = parseFloat(localStorage.getItem("pomo_music_volume") || "0.35");
    musicAudio.play().catch(() => {
      console.warn("Music playback pending user interaction.");
    });
  } else if (musicAudio.src) {
    musicAudio.play().catch(() => {});
  }
});

window.addEventListener("phx:music_resume", () => {
  if (musicAudio.src) {
    musicAudio.play().catch(() => {});
  }
});

window.addEventListener("phx:music_pause", () => {
  musicAudio.pause();
});

window.addEventListener("phx:music_stop", () => {
  musicAudio.pause();
  musicAudio.currentTime = 0;
});

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

