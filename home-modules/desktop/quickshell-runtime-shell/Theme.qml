pragma Singleton

import QtQuick
import Quickshell

// The one place colour lives.
//
// Quickshell singletons reload with the shell, so editing this file restyles
// every surface without touching a single component. Everything below is
// SEMANTIC — components ask for "the colour of a border" or "the tint that
// lifts a floating surface", never for a literal. That is what makes a theme
// swap a matter of editing this file instead of grepping for hex codes, and
// it is why the elevation/scrim/shadow tokens exist at all: they used to be
// 57 hand-written Qt.rgba() literals scattered across the tree, each of which
// silently assumed a dark background.
//
// Palette: shadcn-ui dark, built on Tailwind's zinc ramp for neutrals (the
// same ramp shadcn's own dark theme uses) with the 400-weight status hues,
// which are the lightness that stays legible on a near-black ground.
Singleton {
    id: theme

    // ---- identity -------------------------------------------------------
    readonly property string name: "shadcn-zinc-dark"
    readonly property bool dark: true

    // ---- base surfaces --------------------------------------------------
    // bg → card is the elevation ladder: the further from the background, the
    // closer to zinc-900. Keep the steps small; shadcn reads flat by design.
    readonly property color bg: "#09090b"           // zinc-950, --background
    readonly property color panel: "#0c0c0f"
    readonly property color panelAlt: "#121216"
    readonly property color card: "#18181b"         // zinc-900, --card
    readonly property color cardAlt: "#131316"

    // ---- lines ----------------------------------------------------------
    readonly property color border: "#27272a"       // zinc-800, --border
    readonly property color borderStrong: "#3f3f46" // zinc-700
    readonly property color lineSoft: "#1c1c20"     // separators inside a card

    // ---- foreground -----------------------------------------------------
    readonly property color text: "#fafafa"         // zinc-50, --foreground
    readonly property color textDim: "#d4d4d8"      // zinc-300
    readonly property color muted: "#a1a1aa"        // zinc-400, --muted-foreground
    readonly property color subtle: "#71717a"       // zinc-500, lowest legible

    // ---- accent ---------------------------------------------------------
    // shadcn's primary is near-white on dark rather than a colour; keeping that
    // is what makes the status hues below actually mean something when they
    // appear.
    readonly property color accent: "#e4e4e7"       // zinc-200
    readonly property color accentBg: "#1c1c20"

    // ---- status ---------------------------------------------------------
    // Tailwind 400s. The *Bg variants are the same hue collapsed onto the
    // background — used as chip fills behind the matching foreground colour.
    readonly property color blue: "#60a5fa"
    readonly property color blueBg: "#111a2e"
    readonly property color blueMuted: "#3b5f8f"    // border weight of blue
    readonly property color blueWash: "#101725"     // faintest blue fill
    readonly property color green: "#4ade80"
    readonly property color greenBg: "#0e2318"
    readonly property color red: "#f87171"
    readonly property color redBg: "#2a1416"
    readonly property color amber: "#fbbf24"
    readonly property color amberBg: "#2a1f0d"
    readonly property color orange: "#fb923c"
    readonly property color orangeBg: "#2a1a0e"
    readonly property color teal: "#2dd4bf"
    readonly property color tealBg: "#0c2422"
    readonly property color violet: "#a78bfa"
    readonly property color violetBg: "#1d1830"

    // ---- elevation ------------------------------------------------------
    // On a dark theme a surface is "lifted" by a white film; on a light one it
    // would be a dark film. Components must never write that film themselves,
    // or the shell can only ever be dark. Ordered faint → strong.
    readonly property color elevationFaint: Qt.rgba(1, 1, 1, 0.02)
    readonly property color elevationSoft: Qt.rgba(1, 1, 1, 0.04)
    readonly property color elevation: Qt.rgba(1, 1, 1, 0.06)
    readonly property color elevationStrong: Qt.rgba(1, 1, 1, 0.16)

    // Row hover. Deliberately below elevationFaint — a hover that reads as a
    // fill makes long lists noisy.
    readonly property color hoverWash: Qt.rgba(1, 1, 1, 0.012)
    readonly property color hoverWashStrong: Qt.rgba(1, 1, 1, 0.018)

    // ---- edges and depth ------------------------------------------------
    // Floating surfaces get a light top edge and a dark outer edge; that pair
    // is what reads as "above" without a real shadow.
    readonly property color edgeHighlight: Qt.rgba(1, 1, 1, 0.08)
    readonly property color edgeHighlightSoft: Qt.rgba(1, 1, 1, 0.05)
    readonly property color edgeShadow: Qt.rgba(0, 0, 0, 0.4)
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.55)
    readonly property color shadowSoft: Qt.rgba(0, 0, 0, 0.25)

    // ---- scrims ---------------------------------------------------------
    // Behind modals. Tinted toward the background rather than pure black so a
    // dimmed desktop still looks like this theme.
    readonly property color scrim: Qt.rgba(0.035, 0.035, 0.043, 0.4)
    readonly property color scrimStrong: Qt.rgba(0.035, 0.035, 0.043, 0.8)

    // ---- translucent surfaces -------------------------------------------
    // Frosted panels. Same hue as their opaque counterpart, so a panel over a
    // bright window still belongs to the theme.
    readonly property color panelGlass: Qt.rgba(0.047, 0.047, 0.055, 0.88)
    readonly property color cardGlass: Qt.rgba(0.094, 0.094, 0.106, 0.86)
    readonly property color toastGlass: Qt.rgba(0.047, 0.047, 0.055, 0.92)

    // ---- status washes ---------------------------------------------------
    // Tints derived from the status hues, for selection and urgency fills.
    // Derived rather than hand-written so they follow the palette.
    readonly property color redWash: Qt.rgba(theme.red.r, theme.red.g, theme.red.b, 0.08)
    readonly property color greenWash: Qt.rgba(theme.green.r, theme.green.g, theme.green.b, 0.06)
    readonly property color amberWash: Qt.rgba(theme.amber.r, theme.amber.g, theme.amber.b, 0.08)
    readonly property color tealWash: Qt.rgba(theme.teal.r, theme.teal.g, theme.teal.b, 0.09)
    readonly property color blueSelection: Qt.rgba(theme.blue.r, theme.blue.g, theme.blue.b, 0.10)
    readonly property color subtleWash: Qt.rgba(theme.subtle.r, theme.subtle.g, theme.subtle.b, 0.08)
}
