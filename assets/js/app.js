// Studio's client is deliberately thin: the terminal language is CSS, and every
// piece of state that matters lives on the server. Only two things genuinely
// belong here — the colour theme, which must apply before first paint, and the
// scroll behaviour of the event stream, which depends on where the reader is.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/spectre_studio"
import topbar from "../vendor/topbar"

const THEME_KEY = "spectre-studio:theme"

// Studio is black-first: dark is the default and light is opt-in.
const storedTheme = () => {
  try {
    return window.localStorage.getItem(THEME_KEY)
  } catch (_error) {
    return null
  }
}

const applyTheme = theme => {
  const resolved = theme === "dark" || theme === "light" ? theme : "dark"
  document.documentElement.dataset.theme = resolved
  document.querySelectorAll("[data-theme-toggle]").forEach(button => {
    button.setAttribute("aria-pressed", String(resolved === "dark"))
  })
}

applyTheme(storedTheme())

document.addEventListener("click", event => {
  const toggle = event.target.closest("[data-theme-toggle]")
  if (!toggle) return

  const nextTheme = document.documentElement.dataset.theme === "dark" ? "light" : "dark"

  try {
    window.localStorage.setItem(THEME_KEY, nextTheme)
  } catch (_error) {
    // A browser that refuses storage still gets a working toggle for this page.
  }

  applyTheme(nextTheme)
})

// Follows the tail of an event stream, but yields to the operator: once they
// scroll back to read something, new events stop yanking the viewport away.
const StreamScroll = {
  mounted() {
    this.pinned = true
    this.el.addEventListener("scroll", () => {
      const distance = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
      this.pinned = distance < 24
    })
    this.scrollToTail()
  },
  updated() {
    if (this.pinned) this.scrollToTail()
  },
  scrollToTail() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {StreamScroll, ...colocatedHooks}
})

topbar.config({barColors: {0: "#f5f5f7"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({detail: reloader}) => {
      reloader.enableServerLogs()
      window.liveReloader = reloader
    }
  )
}
