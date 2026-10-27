defmodule AcexGateway.Web.DashboardView do
  @moduledoc """
  Renders the StreamFlix Design System Web Dashboard for AcexGateway.
  A cinematic, dark, content-forward streaming catalog featuring:
  - Real-time P2P Swarm & Bitrate Telemetry
  - Active Broadcast HUD
  - Stream Quick Tester & Smart M3U Playlist Hub (with QR code)
  - 16:9 Cinematic Poster Cards with red glow hover and deep-link launchers
  """

  @doc """
  Returns the raw SVG for the AcexGateway favicon.
  """
  def favicon_svg do
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none">
      <defs>
        <linearGradient id="b" x1="0" y1="0" x2="64" y2="64" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stop-color="#FF2E5B"/>
          <stop offset="60%" stop-color="#E11D48"/>
          <stop offset="100%" stop-color="#9F1239"/>
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="16" fill="url(#b)"/>
      <rect x="0.75" y="0.75" width="62.5" height="62.5" rx="15.25" stroke="rgba(255,255,255,0.25)" stroke-width="1.5"/>
      <path d="M16 21 L26 32 L16 43" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>
      <path d="M29 18 C29 16.5 30.6 15.6 31.8 16.4 L50.2 30.4 C51.4 31.2 51.4 32.8 50.2 33.6 L31.8 47.6 C30.6 48.4 29 47.5 29 46 Z" fill="#FFFFFF"/>
    </svg>
    """
  end

  @doc """
  Renders the complete HTML document for the dashboard.
  """
  def render(base_url, channels) do
    channels_json = Jason.encode!(channels)
    auth_enabled = AcexGateway.Config.auth_enabled?()
    auth_user = AcexGateway.Config.auth_username()
    auth_pass = AcexGateway.Config.auth_password()
    epg_url = AcexGateway.Config.epg_url()
    parsed_uri = URI.parse(base_url)
    server_port = to_string(parsed_uri.port || 8686)

    m3u_display_url =
      if auth_enabled and auth_user != "" and auth_pass != "" do
        "#{base_url}/playlist.m3u8?username=#{URI.encode_www_form(auth_user)}&password=#{URI.encode_www_form(auth_pass)}"
      else
        "#{base_url}/playlist.m3u8"
      end

    """
    <!DOCTYPE html>
    <html lang="en" class="dark">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>AcexGateway ⚡ StreamFlix IPTV Hub</title>
      <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' fill='none'%3E%3Cdefs%3E%3ClinearGradient id='b' x1='0' y1='0' x2='64' y2='64'%3E%3Cstop offset='0%25' stop-color='%23FF2E5B'/%3E%3Cstop offset='60%25' stop-color='%23E11D48'/%3E%3Cstop offset='100%25' stop-color='%239F1239'/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect width='64' height='64' rx='16' fill='url(%23b)'/%3E%3Crect x='0.75' y='0.75' width='62.5' height='62.5' rx='15.25' stroke='rgba(255,255,255,0.25)' stroke-width='1.5'/%3E%3Cpath d='M16 21L26 32L16 43' stroke='%23FFFFFF' stroke-width='5' stroke-linecap='round' stroke-linejoin='round' opacity='0.85'/%3E%3Cpath d='M29 18C29 16.5 30.6 15.6 31.8 16.4L50.2 30.4C51.4 31.2 51.4 32.8 50.2 33.6L31.8 47.6C30.6 48.4 29 47.5 29 46Z' fill='%23FFFFFF'/%3E%3C/svg%3E">
      <link rel="alternate icon" href="/favicon.ico">
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Open+Sans:wght@400;500;600;700&family=Oswald:wght@500;600;700&display=swap" rel="stylesheet">
      <script src="https://cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.min.js"></script>
      <style>
        :root {
          /* StreamFlix Design System Tokens */
          --color-primary: #E11D48;
          --color-primary-hover: #BE123C;
          --color-primary-dim: rgba(225, 29, 72, 0.125);
          --color-primary-border: rgba(225, 29, 72, 0.25);
          --color-secondary: #0F0F0F;
          --color-tertiary: #F5F5F5;
          --surface-base: #0F0F0F;
          --surface-sunken: #080808;
          --surface-card: #1A1A1A;
          --surface-card-hover: #222222;
          --surface-modal: #141414;
          --surface-input: #1A1A1A;

          /* Neutral Borders & Dividers */
          --border-default: #262626;
          --border-subtle: #1C1C1C;
          --border-hover: #525252;
          --border-focus: #E11D48;

          /* Typography Colors */
          --text-primary: #F5F5F5;
          --text-secondary: #A3A3A3;
          --text-tertiary: #737373;

          /* Semantic Status Colors */
          --color-success: #22C55E;
          --color-success-bg: #052E16;
          --color-warning: #F59E0B;
          --color-warning-bg: #451A03;
          --color-error: #EF4444;
          --color-error-bg: #450A0A;
          --color-info: #3B82F6;
          --color-info-bg: rgba(59, 130, 246, 0.15);

          /* Typography Families */
          --font-headline: 'Oswald', sans-serif;
          --font-body: 'Open Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          --font-mono: 'JetBrains Mono', monospace;

          /* 8px Base Spacing Grid */
          --space-xs: 4px;
          --space-sm: 8px;
          --space-md: 16px;
          --space-lg: 24px;
          --space-xl: 32px;
          --space-2xl: 48px;
          --space-3xl: 64px;

          /* Border Radii */
          --radius-sm: 4px;
          --radius-md: 8px;
          --radius-lg: 12px;
          --radius-full: 9999px;

          /* Elevation & Cinematic Red Glow Shadows */
          --shadow-sm: 0 2px 4px rgba(0, 0, 0, 0.5);
          --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.6);
          --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.7);
          --shadow-red: 0 4px 20px rgba(225, 29, 72, 0.4);
          --shadow-hover: 0 8px 30px rgba(225, 29, 72, 0.3);
        }

        /* Global Reset */
        * {
          box-sizing: border-box;
          -webkit-tap-highlight-color: transparent;
          margin: 0;
          padding: 0;
        }

        body {
          font-family: var(--font-body);
          background-color: var(--surface-base);
          color: var(--text-primary);
          min-height: 100vh;
          overflow-x: hidden;
          line-height: 1.5;
          font-size: 16px;
        }

        .container {
          max-width: 1280px;
          margin: 0 auto;
          padding: var(--space-lg) var(--space-md) var(--space-3xl);
        }

        /* -------------------------------------------------------------
           StreamFlix Navigation Bar (Surface Sunken)
           ------------------------------------------------------------- */
        .navbar {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: var(--space-md) var(--space-lg);
          background: var(--surface-sunken);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          margin-bottom: var(--space-xl);
          box-shadow: var(--shadow-sm);
        }

        .brand {
          display: flex;
          align-items: center;
          gap: var(--space-md);
          text-decoration: none;
          color: inherit;
        }

        .brand-icon-box {
          width: 44px;
          height: 44px;
          border-radius: var(--radius-md);
          background: linear-gradient(135deg, #FF2E5B 0%, #E11D48 60%, #9F1239 100%);
          border: 1px solid rgba(255, 255, 255, 0.22);
          display: flex;
          align-items: center;
          justify-content: center;
          color: #FFFFFF;
          box-shadow: 0 4px 18px rgba(225, 29, 72, 0.45);
          flex-shrink: 0;
          transition: transform 0.2s ease, box-shadow 0.2s ease;
        }

        .brand:hover .brand-icon-box {
          transform: scale(1.06);
          box-shadow: 0 6px 24px rgba(225, 29, 72, 0.6);
        }

        .brand-title {
          font-family: var(--font-headline);
          font-size: 26px;
          font-weight: 700;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          color: #FFFFFF;
          display: flex;
          align-items: center;
          gap: var(--space-sm);
          line-height: 1.15;
        }

        .brand-title-accent {
          color: var(--color-primary);
        }

        .brand-badge {
          font-family: var(--font-mono);
          font-size: 11px;
          font-weight: 600;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          padding: 2px 8px;
          border-radius: var(--radius-sm);
          background: var(--color-primary-dim);
          color: var(--color-primary);
          border: 1px solid var(--color-primary-border);
        }

        .brand-sub {
          font-family: var(--font-mono);
          font-size: 11px;
          color: var(--text-tertiary);
          letter-spacing: 0.03em;
          margin-top: 2px;
        }

        .nav-right {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
        }

        /* Status Badge (StreamFlix Status Chips) */
        .status-pill {
          display: inline-flex;
          align-items: center;
          gap: var(--space-sm);
          padding: 6px 12px;
          border-radius: var(--radius-sm);
          font-size: 12px;
          font-weight: 600;
          letter-spacing: 0.02em;
          transition: all 0.3s ease;
        }

        .status-idle {
          color: var(--text-secondary);
          background: var(--surface-card);
          border: 1px solid var(--border-default);
        }

        .status-starting {
          color: var(--color-warning);
          background: var(--color-warning-bg);
          border: 1px solid rgba(245, 158, 11, 0.3);
        }

        .status-live {
          color: var(--color-success);
          background: var(--color-success-bg);
          border: 1px solid rgba(34, 197, 94, 0.4);
          box-shadow: 0 0 16px rgba(34, 197, 94, 0.25);
        }

        .pulse-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: currentColor;
          display: inline-block;
        }

        .pulse-active {
          position: relative;
        }
        .pulse-active::after {
          content: "";
          position: absolute;
          inset: -4px;
          border-radius: 50%;
          border: 2px solid currentColor;
          animation: pulsePing 1.6s cubic-bezier(0, 0, 0.2, 1) infinite;
        }

        @keyframes pulsePing {
          0% { transform: scale(0.8); opacity: 0.9; }
          100% { transform: scale(2.2); opacity: 0; }
        }

        .equalizer {
          display: none;
          align-items: flex-end;
          gap: 2px;
          height: 12px;
        }

        .status-live .equalizer {
          display: inline-flex;
        }

        .equalizer-bar {
          width: 2px;
          background: var(--color-success);
          border-radius: 1px;
          animation: eqDance 0.8s ease-in-out infinite alternate;
        }
        .equalizer-bar:nth-child(1) { height: 40%; animation-delay: 0.1s; }
        .equalizer-bar:nth-child(2) { height: 90%; animation-delay: 0.3s; }
        .equalizer-bar:nth-child(3) { height: 60%; animation-delay: 0.2s; }
        .equalizer-bar:nth-child(4) { height: 100%; animation-delay: 0.4s; }

        @keyframes eqDance {
          0% { height: 20%; }
          100% { height: 100%; }
        }

        /* -------------------------------------------------------------
           Buttons (StreamFlix Specification)
           ------------------------------------------------------------- */
        .btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-sm);
          font-family: var(--font-body);
          font-size: 14px;
          font-weight: 600;
          cursor: pointer;
          border: none;
          outline: none;
          text-decoration: none;
          border-radius: var(--radius-md);
          transition: all 0.2s ease;
          white-space: nowrap;
          line-height: 1.2;
          box-sizing: border-box;
          max-width: 100%;
          padding: 10px 18px;
          min-height: 38px;
          flex-shrink: 0;
        }

        .btn:disabled {
          opacity: 0.35;
          cursor: not-allowed;
          pointer-events: none;
        }

        /* Sizes */
        .btn-sm {
          padding: 8px 14px;
          font-size: 13px;
          min-height: 34px;
        }

        .btn-md {
          padding: 10px 20px;
          font-size: 15px;
          min-height: 40px;
        }

        .btn-lg {
          padding: 12px 28px;
          font-size: 16px;
          min-height: 48px;
        }

        .btn-xs {
          padding: 4px 8px;
          font-size: 12px;
          min-height: 26px;
          border-radius: var(--radius-sm);
        }

        .btn-icon {
          padding: 0;
          width: 34px;
          height: 34px;
          min-width: 34px;
          flex-shrink: 0;
        }

        .btn-icon.btn-xs {
          width: 26px;
          height: 26px;
          min-width: 26px;
        }

        /* Variants */
        .btn-primary {
          background: var(--color-primary);
          color: #FFFFFF;
          box-shadow: var(--shadow-red);
        }
        .btn-primary:hover {
          background: var(--color-primary-hover);
          box-shadow: var(--shadow-hover);
        }

        .btn-secondary {
          background: var(--border-default);
          color: var(--color-tertiary);
          border: 1px solid var(--border-default);
        }
        .btn-secondary:hover {
          background: #374151;
          color: #FFFFFF;
        }

        .btn-ghost {
          background: transparent;
          color: var(--color-tertiary);
          border: 1px solid var(--border-hover);
        }
        .btn-ghost:hover {
          background: var(--border-default);
          color: #FFFFFF;
        }

        .btn-destructive, .btn-danger {
          background: var(--color-error);
          color: #FFFFFF;
        }
        .btn-destructive:hover, .btn-danger:hover {
          background: #DC2626;
        }

        /* -------------------------------------------------------------
           Chips & Badges (StreamFlix Specification)
           ------------------------------------------------------------- */
        .chip-filter {
          display: inline-flex;
          align-items: center;
          gap: var(--space-xs);
          padding: 4px 10px;
          font-size: 12px;
          font-weight: 600;
          border-radius: var(--radius-sm);
          background: var(--color-primary-dim);
          color: var(--color-primary);
          border: 1px solid var(--color-primary-border);
          line-height: 1.4;
        }

        .chip-status-success {
          display: inline-flex;
          align-items: center;
          gap: var(--space-xs);
          padding: 4px 10px;
          font-size: 12px;
          font-weight: 600;
          border-radius: var(--radius-sm);
          background: var(--color-success-bg);
          color: var(--color-success);
          line-height: 1.4;
        }

        .chip-status-warning {
          display: inline-flex;
          align-items: center;
          gap: var(--space-xs);
          padding: 4px 10px;
          font-size: 12px;
          font-weight: 600;
          border-radius: var(--radius-sm);
          background: var(--color-warning-bg);
          color: var(--color-warning);
          line-height: 1.4;
        }

        .chip-status-neutral {
          display: inline-flex;
          align-items: center;
          gap: var(--space-xs);
          padding: 4px 10px;
          font-size: 12px;
          font-weight: 600;
          border-radius: var(--radius-sm);
          background: #262626;
          color: var(--text-secondary);
          line-height: 1.4;
        }

        /* Backward-compatible badge aliases */
        .badge {
          display: inline-flex;
          align-items: center;
          padding: 4px 8px;
          border-radius: var(--radius-sm);
          font-size: 12px;
          font-weight: 600;
        }
        .badge-cyan { background: var(--color-primary-dim); color: var(--color-primary); border: 1px solid var(--color-primary-border); }
        .badge-violet { background: #262626; color: var(--text-primary); }
        .badge-emerald { background: var(--color-success-bg); color: var(--color-success); }

        /* -------------------------------------------------------------
           Active Broadcast Banner (Cinema HUD)
           ------------------------------------------------------------- */
        .active-broadcast-hud {
          display: none;
          background: var(--surface-modal);
          border: 1px solid var(--color-primary);
          border-radius: var(--radius-md);
          padding: var(--space-md) var(--space-lg);
          margin-bottom: var(--space-xl);
          box-shadow: var(--shadow-hover);
          position: relative;
          overflow: hidden;
        }

        /* -------------------------------------------------------------
           Action Panels (Quick Tester + M3U Hub)
           ------------------------------------------------------------- */
        .action-panels-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-md);
          margin-bottom: var(--space-xl);
        }

        .panel-box {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          padding: var(--space-lg);
          box-shadow: var(--shadow-sm);
          display: flex;
          flex-direction: column;
          gap: var(--space-md);
        }

        .panel-head {
          display: flex;
          align-items: flex-start;
          gap: var(--space-md);
        }

        .panel-icon-wrap {
          width: 40px;
          height: 40px;
          border-radius: var(--radius-md);
          background: var(--color-primary-dim);
          border: 1px solid var(--color-primary-border);
          color: var(--color-primary);
          display: flex;
          align-items: center;
          justify-content: center;
          flex-shrink: 0;
        }

        .panel-head h2 {
          font-family: var(--font-headline);
          font-size: 22px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: #FFFFFF;
          line-height: 1.2;
        }

        .panel-head p {
          font-size: 14px;
          color: var(--text-secondary);
          margin-top: 4px;
          line-height: 1.4;
        }

        .input-row {
          display: flex;
          gap: var(--space-sm);
          align-items: stretch;
          width: 100%;
        }

        .input-row .btn {
          flex-shrink: 0;
          padding: 0 20px;
          min-width: 96px;
        }

        .input-row .btn.btn-sm {
          min-width: 76px;
          padding: 0 16px;
        }

        .text-input-styled {
          flex: 1;
          min-width: 0;
          background: var(--surface-input);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          padding: 10px 14px;
          font-family: var(--font-mono);
          font-size: 14px;
          color: var(--text-primary);
          outline: none;
          transition: border-color 0.2s, box-shadow 0.2s;
        }

        .panel-actions-row {
          display: flex;
          gap: var(--space-sm);
          justify-content: flex-end;
          flex-wrap: wrap;
          width: 100%;
        }

        .text-input-styled:hover {
          border-color: var(--border-hover);
        }

        .text-input-styled:focus {
          border-color: var(--border-focus);
          box-shadow: 0 0 0 3px rgba(225, 29, 72, 0.25);
        }

        .detected-hash-badge {
          display: none;
          align-items: center;
          gap: var(--space-sm);
          padding: 8px 12px;
          background: var(--color-success-bg);
          border-radius: var(--radius-sm);
          font-family: var(--font-mono);
          font-size: 13px;
          color: var(--color-success);
          word-break: break-all;
        }

        /* -------------------------------------------------------------
           Channel Lineup Catalog (Cinematic Posters)
           ------------------------------------------------------------- */
        .lineup-section {
          margin-top: var(--space-xl);
        }

        .lineup-toolbar {
          display: flex;
          justify-content: space-between;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--space-md);
          margin-bottom: var(--space-md);
        }

        .toolbar-title {
          font-family: var(--font-headline);
          font-size: 32px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: #FFFFFF;
          display: flex;
          align-items: center;
          gap: var(--space-sm);
        }

        .toolbar-right {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
          flex-wrap: wrap;
        }

        .toolbar-actions-group {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
        }

        .search-box-wrap {
          position: relative;
          display: flex;
          align-items: center;
          width: 280px;
        }

        .search-icon-left {
          position: absolute;
          left: 12px;
          color: var(--text-tertiary);
          pointer-events: none;
        }

        .search-input {
          width: 100%;
          background: var(--surface-input);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          padding: 8px 38px 8px 36px;
          font-family: var(--font-body);
          font-size: 14px;
          color: var(--text-primary);
          outline: none;
          transition: border-color 0.2s, box-shadow 0.2s;
        }

        .search-input:hover {
          border-color: var(--border-hover);
        }

        .search-input:focus {
          border-color: var(--border-focus);
          box-shadow: 0 0 0 3px rgba(225, 29, 72, 0.25);
        }

        .kbd-shortcut {
          position: absolute;
          right: 12px;
          padding: 2px 6px;
          font-family: var(--font-mono);
          font-size: 11px;
          background: var(--border-default);
          color: var(--text-secondary);
          border-radius: var(--radius-sm);
          pointer-events: none;
        }

        .view-toggle {
          display: flex;
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          overflow: hidden;
        }

        .view-btn {
          background: transparent;
          border: none;
          padding: 8px 12px;
          color: var(--text-secondary);
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: all 0.2s;
        }

        .view-btn:hover {
          color: #FFFFFF;
        }

        .view-btn.active {
          background: var(--border-default);
          color: var(--color-primary);
        }

        /* Category Filter Tabs */
        .category-tabs {
          display: flex;
          gap: var(--space-sm);
          overflow-x: auto;
          -webkit-overflow-scrolling: touch;
          padding-bottom: var(--space-md);
          margin-bottom: var(--space-md);
          scrollbar-width: thin;
        }

        .tab-btn {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-sm);
          padding: 6px 14px;
          font-family: var(--font-body);
          font-size: 13px;
          font-weight: 600;
          color: var(--text-secondary);
          cursor: pointer;
          display: inline-flex;
          align-items: center;
          gap: 6px;
          white-space: nowrap;
          transition: all 0.2s;
        }

        .tab-btn:hover {
          background: var(--border-default);
          color: #FFFFFF;
          border-color: var(--border-hover);
        }

        .tab-btn.active {
          background: var(--color-primary-dim);
          color: var(--color-primary);
          border-color: var(--color-primary-border);
          box-shadow: 0 0 12px rgba(225, 29, 72, 0.2);
        }

        /* -------------------------------------------------------------
           Channel Card: 16:9 Cinematic Thumbnail / Poster (DESIGN.md)
           ------------------------------------------------------------- */
        .channel-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(290px, 1fr));
          gap: var(--space-md);
        }

        .channel-card-sf {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          overflow: hidden;
          box-shadow: var(--shadow-sm);
          display: flex;
          flex-direction: column;
          position: relative;
          transition: transform 0.25s cubic-bezier(0.2, 0, 0, 1), box-shadow 0.25s ease, border-color 0.25s ease;
        }

        /* Rule 1 & 6: Scale 1.04 + Red Glow shadow-hover on Card Hover */
        .channel-card-sf:hover {
          transform: scale(1.04);
          box-shadow: var(--shadow-hover);
          border-color: rgba(225, 29, 72, 0.4);
          z-index: 2;
        }

        .poster-box {
          position: relative;
          width: 100%;
          aspect-ratio: 16 / 9;
          background: #121212;
          overflow: hidden;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .poster-img {
          width: 100%;
          height: 100%;
          object-fit: cover;
          transition: transform 0.35s ease;
        }

        .channel-card-sf:hover .poster-img {
          transform: scale(1.06);
        }

        .poster-fallback {
          width: 100%;
          height: 100%;
          background: radial-gradient(circle at 50% 30%, #262626 0%, #111111 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-headline);
          font-size: 42px;
          font-weight: 700;
          color: rgba(255, 255, 255, 0.25);
          letter-spacing: 0.05em;
        }

        .poster-scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(180deg, rgba(15,15,15,0.2) 0%, rgba(26,26,26,0.95) 100%);
          pointer-events: none;
        }

        .poster-badges-top {
          position: absolute;
          top: 10px;
          left: 10px;
          right: 10px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          pointer-events: none;
          z-index: 1;
        }

        /* Center Red Play Button on Poster Hover */
        .poster-play-btn {
          position: absolute;
          width: 52px;
          height: 52px;
          border-radius: var(--radius-full);
          background: var(--color-primary);
          color: #FFFFFF;
          border: none;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          opacity: 0;
          transform: scale(0.85);
          box-shadow: var(--shadow-red);
          transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
          z-index: 2;
        }

        .poster-play-btn svg {
          margin-left: 3px;
        }

        .channel-card-sf:hover .poster-play-btn {
          opacity: 1;
          transform: scale(1);
        }

        .poster-play-btn:hover {
          background: var(--color-primary-hover);
          transform: scale(1.1) !important;
        }

        /* Card Content Area */
        .card-content {
          padding: var(--space-md);
          display: flex;
          flex-direction: column;
          flex: 1;
          gap: var(--space-sm);
        }

        .card-head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--space-sm);
        }

        .card-title {
          font-family: var(--font-headline);
          font-size: 19px;
          font-weight: 600;
          letter-spacing: 0.02em;
          color: #FFFFFF;
          line-height: 1.25;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
        }

        .card-type-tag {
          font-family: var(--font-mono);
          font-size: 11px;
          color: var(--text-tertiary);
          background: var(--border-default);
          padding: 2px 6px;
          border-radius: var(--radius-sm);
          text-transform: uppercase;
        }

        .card-slug {
          font-family: var(--font-mono);
          font-size: 12px;
          color: var(--text-tertiary);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        /* Sources Accordion */
        .sources-accordion {
          border-top: 1px solid var(--border-default);
          padding-top: var(--space-sm);
          margin-top: auto;
        }

        .sources-toggle {
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 13px;
          font-weight: 600;
          color: var(--text-secondary);
          cursor: pointer;
          user-select: none;
          padding: 4px 0;
          transition: color 0.2s;
        }

        .sources-toggle:hover {
          color: #FFFFFF;
        }

        .sources-list {
          display: none;
          flex-direction: column;
          gap: 4px;
          margin-top: 6px;
          max-height: 140px;
          overflow-y: auto;
        }

        .sources-list.show {
          display: flex;
        }

        .source-item {
          display: flex;
          align-items: center;
          gap: 6px;
          padding: 5px 8px;
          background: #111111;
          border-radius: var(--radius-sm);
          font-family: var(--font-mono);
          font-size: 12px;
          color: var(--text-secondary);
        }

        .card-actions-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: var(--space-sm);
          margin-top: var(--space-sm);
          padding-top: var(--space-sm);
          border-top: 1px solid var(--border-default);
          flex-wrap: wrap;
        }

        .card-icon-actions {
          display: flex;
          align-items: center;
          gap: 4px;
        }

        /* -------------------------------------------------------------
           Channel Table View (StreamFlix List Component)
           ------------------------------------------------------------- */
        .table-container {
          width: 100%;
          overflow-x: auto;
          -webkit-overflow-scrolling: touch;
          display: none;
          background: var(--surface-card);
          border-radius: var(--radius-md);
          border: 1px solid var(--border-default);
          box-shadow: var(--shadow-sm);
        }

        .table-container.show {
          display: block;
        }

        .channel-table {
          width: 100%;
          min-width: 650px;
          border-collapse: collapse;
          background: transparent;
        }

        .channel-table th {
          background: var(--surface-sunken);
          padding: 12px 16px;
          text-align: left;
          font-family: var(--font-headline);
          font-size: 14px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          color: var(--text-secondary);
          border-bottom: 1px solid var(--border-default);
        }

        .channel-table td {
          padding: 0 16px;
          height: 56px;
          vertical-align: middle;
          border-bottom: 1px solid var(--border-default);
          font-size: 14px;
        }

        .channel-table tr:hover td {
          background: var(--surface-card-hover);
        }

        .table-thumb {
          width: 44px;
          height: 28px;
          border-radius: var(--radius-sm);
          object-fit: cover;
          background: #111111;
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-headline);
          font-size: 12px;
          font-weight: 700;
          color: var(--text-secondary);
        }

        /* -------------------------------------------------------------
           Modals & Dialogs (StreamFlix Specification)
           ------------------------------------------------------------- */
        .modal-overlay {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.8);
          backdrop-filter: blur(12px);
          -webkit-backdrop-filter: blur(12px);
          display: none;
          align-items: center;
          justify-content: center;
          z-index: 1000;
          padding: var(--space-md);
        }

        .modal-overlay.active {
          display: flex;
          animation: fadeIn 0.2s ease;
        }

        .modal-window {
          background: var(--surface-modal);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-lg);
          box-shadow: var(--shadow-lg);
          width: 100%;
          max-width: 540px;
          padding: var(--space-lg);
          position: relative;
        }

        .modal-top {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: var(--space-lg);
        }

        .modal-top h3 {
          font-family: var(--font-headline);
          font-size: 24px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.03em;
          color: #FFFFFF;
        }

        .form-group {
          margin-bottom: var(--space-md);
        }

        .form-label {
          display: block;
          font-size: 14px;
          font-weight: 600;
          color: var(--color-tertiary);
          margin-bottom: 4px;
        }

        .form-control {
          width: 100%;
          background: var(--surface-input);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          padding: 10px 14px;
          font-family: var(--font-body);
          font-size: 14px;
          color: var(--text-primary);
          outline: none;
          transition: border-color 0.2s, box-shadow 0.2s;
        }

        .form-control:hover {
          border-color: var(--border-hover);
        }

        .form-control:focus {
          border-color: var(--border-focus);
          box-shadow: 0 0 0 3px rgba(225, 29, 72, 0.25);
        }

        textarea.form-control {
          resize: vertical;
          font-family: var(--font-mono);
          font-size: 13px;
        }

        .form-hint {
          font-size: 12px;
          color: var(--text-tertiary);
          margin-top: 4px;
        }

        .modal-grid-3col {
          display: grid;
          grid-template-columns: 1fr 1fr 1fr;
          gap: var(--space-md);
        }

        /* Launcher Links Grid */
        .launcher-links-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--space-sm);
          margin-top: var(--space-sm);
        }

        .app-launch-card {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
          padding: var(--space-md);
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          color: var(--text-primary);
          text-decoration: none;
          transition: all 0.2s ease;
        }

        .app-launch-card:hover {
          background: var(--surface-card-hover);
          border-color: var(--border-hover);
          transform: translateY(-2px);
          box-shadow: var(--shadow-sm);
        }

        /* QR Code Modal Box */
        .qr-card-box {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: var(--space-md);
          text-align: center;
        }

        .qr-img-wrap {
          background: #FFFFFF;
          padding: var(--space-md);
          border-radius: var(--radius-md);
          box-shadow: var(--shadow-md);
          display: inline-block;
        }

        .qr-img-wrap img {
          display: block;
          width: 220px;
          height: 220px;
        }

        /* Toast Shelf */
        .toast-shelf {
          position: fixed;
          bottom: var(--space-lg);
          right: var(--space-lg);
          z-index: 2000;
          display: flex;
          flex-direction: column;
          gap: var(--space-sm);
          pointer-events: none;
        }

        .toast-message {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          color: #FFFFFF;
          padding: 12px 18px;
          border-radius: var(--radius-md);
          box-shadow: var(--shadow-lg);
          font-size: 14px;
          font-weight: 500;
          display: flex;
          align-items: center;
          gap: var(--space-sm);
          pointer-events: auto;
          transform: translateY(15px);
          opacity: 0;
          animation: toastSlideUp 0.25s forwards cubic-bezier(0.16, 1, 0.3, 1);
        }

        @keyframes toastSlideUp {
          to { transform: translateY(0); opacity: 1; }
        }

        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }

        /* Dashboard Footer */
        .dashboard-footer {
          margin-top: var(--space-2xl);
          padding-top: var(--space-lg);
          border-top: 1px solid var(--border-default);
          display: flex;
          align-items: center;
          justify-content: space-between;
          color: var(--text-tertiary);
          font-size: 13px;
          flex-wrap: wrap;
          gap: var(--space-md);
        }

        .footer-left {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
        }

        .footer-logo {
          width: 24px;
          height: 24px;
          border-radius: var(--radius-sm);
          background: linear-gradient(135deg, #FF2E5B 0%, #E11D48 100%);
          border: 1px solid rgba(255, 255, 255, 0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          box-shadow: 0 2px 8px rgba(225, 29, 72, 0.35);
          flex-shrink: 0;
        }

        .footer-brand-name {
          font-family: var(--font-headline);
          font-weight: 700;
          letter-spacing: 0.05em;
          text-transform: uppercase;
          color: #FFFFFF;
          font-size: 15px;
        }

        .footer-sep {
          color: var(--border-hover);
        }

        .footer-right {
          display: flex;
          align-items: center;
          gap: var(--space-sm);
          font-family: var(--font-mono);
          font-size: 12px;
        }

        /* Responsive Breakpoints (Mobile & Tablet) */
        @media (max-width: 860px) {
          .action-panels-grid { grid-template-columns: 1fr; }
          .navbar { flex-direction: column; align-items: stretch; gap: var(--space-md); }
          .nav-right { width: 100%; justify-content: space-between; }
          .launcher-links-grid { grid-template-columns: 1fr; }
        }

        @media (max-width: 768px) {
          .container {
            padding: 16px 12px 64px;
          }
          .lineup-toolbar {
            flex-direction: column;
            align-items: stretch;
            gap: 12px;
          }
          .toolbar-title {
            font-size: 22px;
          }
          .toolbar-right {
            width: 100%;
            flex-direction: column;
            align-items: stretch;
            gap: 10px;
          }
          .search-box-wrap {
            width: 100%;
          }
          .toolbar-actions-group {
            display: flex;
            justify-content: space-between;
            align-items: center;
            width: 100%;
          }
          .active-broadcast-hud {
            padding: 14px 12px;
          }
          .active-stream-card {
            flex-direction: column;
            align-items: stretch;
            gap: 10px;
          }
          .active-stream-actions {
            width: 100%;
            display: flex;
            justify-content: space-between;
          }
          .active-stream-actions .btn {
            flex: 1;
            justify-content: center;
          }
        }

        @media (max-width: 640px) {
          .container {
            padding: 12px 10px 48px;
          }
          .navbar {
            padding: 12px 14px;
            gap: 10px;
            margin-bottom: var(--space-md);
          }
          .brand-icon-box {
            width: 36px;
            height: 36px;
          }
          .brand-title {
            font-size: 19px;
          }
          .brand-sub {
            font-size: 10px;
          }
          .nav-right {
            gap: 6px;
          }
          .status-pill {
            padding: 4px 8px;
            font-size: 11px;
          }
          .panel-box {
            padding: 16px 14px;
            gap: 12px;
          }
          .panel-head {
            gap: 12px;
          }
          .panel-icon-wrap {
            width: 34px;
            height: 34px;
          }
          .panel-head h2 {
            font-size: 18px;
          }
          .panel-head p {
            font-size: 13px;
          }
          .panel-actions-row {
            justify-content: stretch;
          }
          .panel-actions-row .btn {
            flex: 1;
            min-width: 120px;
            justify-content: center;
          }
          .category-tabs {
            gap: 6px;
            margin-bottom: 12px;
            padding-bottom: 8px;
          }
          .channel-grid {
            grid-template-columns: 1fr;
            gap: var(--space-md);
          }
          .card-content {
            padding: 12px;
            gap: 6px;
          }
          .card-title {
            font-size: 17px;
          }
          .card-actions-row {
            gap: 6px;
          }
          .modal-overlay {
            padding: 10px;
          }
          .modal-window {
            width: 100%;
            padding: 16px 14px;
            max-height: 94vh;
            overflow-y: auto;
            -webkit-overflow-scrolling: touch;
          }
          .modal-top h3 {
            font-size: 20px;
          }
          .modal-grid-2col,
          .modal-grid-3col {
            grid-template-columns: 1fr !important;
            gap: var(--space-sm) !important;
          }
          .toast-shelf {
            right: 12px;
            bottom: 12px;
            left: 12px;
          }
          .toast-message {
            width: 100%;
            font-size: 13px;
            padding: 10px 14px;
          }
          .dashboard-footer {
            flex-direction: column;
            align-items: flex-start;
            gap: 10px;
            margin-top: var(--space-xl);
            padding-top: var(--space-md);
          }
        }

        /* Modern Toggle Switch & Status Badges */
        .switch {
          position: relative;
          display: inline-block;
          width: 44px;
          height: 24px;
          flex-shrink: 0;
        }
        .switch input {
          opacity: 0;
          width: 0;
          height: 0;
        }
        .slider {
          position: absolute;
          cursor: pointer;
          top: 0; left: 0; right: 0; bottom: 0;
          background-color: #374151;
          transition: .25s ease;
          border-radius: 24px;
          border: 1px solid rgba(255, 255, 255, 0.12);
        }
        .slider:before {
          position: absolute;
          content: "";
          height: 18px;
          width: 18px;
          left: 2px;
          bottom: 2px;
          background-color: #FFFFFF;
          transition: .25s ease;
          border-radius: 50%;
          box-shadow: 0 1px 4px rgba(0,0,0,0.5);
        }
        input:checked + .slider {
          background-color: #10B981;
        }
        input:checked + .slider:before {
          transform: translateX(20px);
        }
        .badge-status {
          display: inline-flex;
          align-items: center;
          padding: 2px 8px;
          font-size: 11px;
          font-weight: 700;
          border-radius: 12px;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .badge-status.badge-enabled {
          background: rgba(16, 185, 129, 0.18);
          color: #10B981;
          border: 1px solid rgba(16, 185, 129, 0.35);
        }
        .badge-status.badge-disabled {
          background: rgba(156, 163, 175, 0.15);
          color: #9CA3AF;
          border: 1px solid rgba(156, 163, 175, 0.25);
        }

        /* 1-Click Update Badge & Button */
        .update-badge-btn {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-full);
          padding: 5px 12px;
          font-family: var(--font-mono);
          font-size: 11px;
          font-weight: 600;
          color: var(--text-secondary);
          cursor: pointer;
          transition: all 0.2s ease;
          text-decoration: none;
        }

        .update-badge-btn:hover {
          border-color: var(--color-primary);
          color: #FFFFFF;
          background: var(--surface-sunken);
        }

        .update-badge-btn.has-update {
          background: rgba(225, 29, 72, 0.15);
          border-color: var(--color-primary);
          color: #FF5A79;
          animation: pulse-update-btn 2.2s infinite;
        }

        @keyframes pulse-update-btn {
          0%, 100% { box-shadow: 0 0 0 0 rgba(225, 29, 72, 0.45); }
          50% { box-shadow: 0 0 0 7px rgba(225, 29, 72, 0); }
        }

        /* Fleet Health Summary Banner */
        .fleet-health-banner {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-lg);
          padding: 16px 20px;
          margin-bottom: var(--space-lg);
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: 16px;
        }

        .fleet-metrics-group {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 12px 20px;
        }

        .fleet-metric-item {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .fleet-metric-icon {
          width: 32px;
          height: 32px;
          border-radius: var(--radius-sm);
          background: var(--surface-sunken);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 15px;
          border: 1px solid var(--border-subtle);
        }

        .fleet-metric-val {
          font-family: var(--font-headline);
          font-size: 18px;
          font-weight: 700;
          color: #FFFFFF;
          line-height: 1.1;
        }

        .fleet-metric-label {
          font-size: 11px;
          color: var(--text-secondary);
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }

        /* Fleet Filter Chips */
        .fleet-filter-bar {
          display: flex;
          align-items: center;
          gap: 8px;
          margin-bottom: var(--space-md);
          overflow-x: auto;
          padding-bottom: 2px;
        }

        .filter-tab-pill {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          color: var(--text-secondary);
          padding: 6px 14px;
          border-radius: var(--radius-full);
          font-size: 13px;
          font-weight: 600;
          cursor: pointer;
          white-space: nowrap;
          transition: all 0.2s ease;
        }

        .filter-tab-pill:hover {
          color: #FFFFFF;
          border-color: var(--border-hover);
        }

        .filter-tab-pill.active {
          background: var(--color-primary-dim);
          border-color: var(--color-primary);
          color: #FFFFFF;
        }

        /* Interactive Source Card Row */
        .source-card-item {
          display: flex;
          align-items: center;
          gap: 8px;
          background: var(--surface-sunken);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-sm);
          padding: 6px 10px;
          margin-bottom: 6px;
          transition: border-color 0.15s ease;
        }

        .source-card-item:hover {
          border-color: var(--border-hover);
        }

        .source-card-rank {
          font-family: var(--font-headline);
          font-size: 12px;
          font-weight: 700;
          padding: 2px 6px;
          border-radius: 4px;
          white-space: nowrap;
        }

        .source-card-rank.rank-primary {
          background: rgba(225, 29, 72, 0.2);
          color: var(--color-primary);
          border: 1px solid rgba(225, 29, 72, 0.4);
        }

        .source-card-rank.rank-backup {
          background: rgba(255, 255, 255, 0.05);
          color: var(--text-secondary);
          border: 1px solid var(--border-subtle);
        }

        .source-card-hash {
          flex: 1;
          font-family: var(--font-mono);
          font-size: 12px;
          color: #FFFFFF;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .source-card-actions {
          display: flex;
          align-items: center;
          gap: 4px;
        }

        .source-card-btn {
          background: transparent;
          border: 1px solid var(--border-default);
          color: var(--text-secondary);
          width: 24px;
          height: 24px;
          border-radius: 4px;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          font-size: 11px;
          transition: all 0.15s ease;
        }

        .source-card-btn:hover:not(:disabled) {
          background: var(--surface-card-hover);
          color: #FFFFFF;
          border-color: var(--border-hover);
        }

        .source-card-btn:disabled {
          opacity: 0.3;
          cursor: not-allowed;
        }

        .source-card-btn.btn-remove:hover {
          background: rgba(239, 68, 68, 0.15);
          color: var(--color-danger);
          border-color: rgba(239, 68, 68, 0.4);
        }

        /* Web Player Modal Video Responsive Box */
        .video-player-box {
          position: relative;
          width: 100%;
          aspect-ratio: 16 / 9;
          background: #000000;
          border-radius: var(--radius-md);
          overflow: hidden;
          border: 1px solid var(--border-default);
          display: flex;
          align-items: center;
          justify-content: center;
        }

        #webVideoPlayer {
          width: 100%;
          height: 100%;
          object-fit: contain;
          outline: none;
        }

        .video-player-hud {
          position: absolute;
          top: 10px;
          left: 10px;
          right: 10px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          pointer-events: none;
          z-index: 5;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <!-- Top Navigation Bar (Surface Sunken) -->
        <header class="navbar">
          <a href="/" class="brand">
            <div class="brand-icon-box">
              <svg width="24" height="24" viewBox="0 0 64 64" fill="none">
                <path d="M16 21 L26 32 L16 43" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>
                <path d="M29 18 C29 16.5 30.6 15.6 31.8 16.4 L50.2 30.4 C51.4 31.2 51.4 32.8 50.2 33.6 L31.8 47.6 C30.6 48.4 29 47.5 29 46 Z" fill="#FFFFFF"/>
              </svg>
            </div>
            <div>
              <div class="brand-title">
                Acex<span class="brand-title-accent">Gateway</span>
                <span class="brand-badge">v#{AcexGateway.version()}</span>
              </div>
            </div>
          </a>

          <div class="nav-right">
            <button id="updateBadgeBtn" class="update-badge-btn" onclick="openUpdateModal()" title="Kiểm tra & Cập nhật hệ thống">
              <span id="updateBadgeIcon">⚡</span>
              <span id="updateBadgeText">v#{AcexGateway.version()}</span>
            </button>
            <div id="statusPill" class="status-pill status-idle">
              <span id="statusDot" class="pulse-dot"></span>
              <span id="statusText">SYSTEM READY</span>
              <div class="equalizer">
                <div class="equalizer-bar"></div>
                <div class="equalizer-bar"></div>
                <div class="equalizer-bar"></div>
                <div class="equalizer-bar"></div>
              </div>
            </div>
          </div>
        </header>

        <!-- Dual Action Hubs: Instant Tester + M3U Playlist -->
        <section class="action-panels-grid">
          <!-- 1. Quick Stream Launcher -->
          <div class="panel-box">
            <div class="panel-head">
              <div class="panel-icon-wrap">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                  <polygon points="5 3 19 12 5 21 5 3"/>
                </svg>
              </div>
              <div>
                <h2>Instant Stream Tester</h2>
                <p>Paste a Content ID or acestream:// link to probe or stream immediately:</p>
              </div>
            </div>

            <div class="input-row">
              <input type="text" id="quickTestInput" class="text-input-styled" placeholder="e.g., a895ab5bcc8beba2d2aa6d5aa332927f005baa65" oninput="handleQuickInput(this.value)">
              <button class="btn btn-primary btn-md" onclick="launchQuickStream()">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                <span>Play</span>
              </button>
            </div>

            <div id="quickDetectedBox" class="detected-hash-badge">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>
              <span id="quickDetectedText">Clean hash detected: ...</span>
            </div>

            <div class="panel-actions-row">
              <button class="btn btn-secondary btn-sm" onclick="copyQuickStreamUrl(this)">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                <span>Copy Link</span>
              </button>
              <button class="btn btn-secondary btn-sm" onclick="fillAddModalWithQuick()">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                <span>Save Channel</span>
              </button>
            </div>
          </div>

          <!-- 2. Smart M3U Playlist Hub -->
          <div class="panel-box">
            <div class="panel-head">
              <div class="panel-icon-wrap">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              </div>
              <div>
                <h2>Smart TV M3U8 Playlist</h2>
                <p>Import into TiviMate, IPTV Smarters, Apple TV, or scan QR code on mobile:</p>
              </div>
            </div>

            <div class="input-row">
              <input type="text" id="m3uUrlInput" class="text-input-styled" readonly value="#{m3u_display_url}">
              <button id="copyM3uBtn" class="btn btn-primary btn-md" onclick="copyM3uUrl(this)">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                <span>Copy</span>
              </button>
            </div>

            <div class="panel-actions-row">
              <button class="btn btn-secondary btn-sm" onclick="openXtreamModal()">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 11a9 9 0 0 1 9 9"/><path d="M4 4a16 16 0 0 1 16 16"/><circle cx="5" cy="19" r="1"/></svg>
                <span>Xtream Codes</span>
              </button>
              <button class="btn btn-secondary btn-sm" onclick="openQrModal()">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>
                <span>QR Code</span>
              </button>
              <a id="m3uDownloadLink" href="#{m3u_display_url}" download="acex_playlist.m3u8" class="btn btn-secondary btn-sm">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <span>Download M3U8</span>
              </a>
            </div>
          </div>
        </section>

        <!-- Fleet Health Summary Banner -->
        <section class="fleet-health-banner">
          <div class="fleet-metrics-group">
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon">📺</div>
              <div>
                <div class="fleet-metric-val" id="metricTotalChannels">0</div>
                <div class="fleet-metric-label">Tổng số kênh</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-success);">🛡️</div>
              <div>
                <div class="fleet-metric-val" id="metricMultiChannels">0</div>
                <div class="fleet-metric-label">Đa nguồn dự phòng</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-warning);">⚠️</div>
              <div>
                <div class="fleet-metric-val" id="metricSingleChannels">0</div>
                <div class="fleet-metric-label">Đơn nguồn (1 source)</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-primary);">🔴</div>
              <div>
                <div class="fleet-metric-val" id="metricLiveChannels">0</div>
                <div class="fleet-metric-label">Đang phát (Active)</div>
              </div>
            </div>
          </div>

          <div style="display: flex; align-items: center; gap: 8px;">
            <button class="btn btn-secondary btn-sm" onclick="pruneAllDeadSources(this)" title="Quét và tự động gỡ bỏ các Content ID chết trên các kênh đa nguồn" style="color: var(--color-danger); border-color: rgba(239, 68, 68, 0.4);">
              <span>🧹 Dọn nguồn chết toàn bộ</span>
            </button>
          </div>
        </section>

        <!-- Channel Lineup Catalog -->
        <section class="lineup-section">
          <!-- Fleet Filter Chips -->
          <div class="fleet-filter-bar">
            <button class="filter-tab-pill active" id="filterPillAll" onclick="setFleetFilter('all')">Tất cả (<span id="countPillAll">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillLive" onclick="setFleetFilter('live')">🔴 Đang phát (<span id="countPillLive">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillMulti" onclick="setFleetFilter('multi')">🛡️ Đa nguồn (<span id="countPillMulti">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillSingle" onclick="setFleetFilter('single')">⚠️ Đơn nguồn (<span id="countPillSingle">0</span>)</button>
          </div>

          <div class="lineup-toolbar">
            <h2 class="toolbar-title">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
                <polygon points="5 3 19 12 5 21 5 3"/>
              </svg>
              <span>CHANNELS LINEUP</span>
              <span id="channelCountBadge" class="chip-filter">0 channels</span>
            </h2>

            <div class="toolbar-right">
              <div class="search-box-wrap">
                <svg class="search-icon-left" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <input type="text" id="channelSearch" class="search-input" placeholder="Search channels, categories..." oninput="filterChannels()">
                <span class="kbd-shortcut">/</span>
              </div>

              <div class="toolbar-actions-group">
                <div class="view-toggle">
                  <button id="viewGridBtn" class="view-btn active" onclick="switchView('grid')" title="16:9 Poster Grid View">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>
                  </button>
                  <button id="viewListBtn" class="view-btn" onclick="switchView('list')" title="Compact List View">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
                  </button>
                </div>

                <button class="btn btn-secondary btn-sm" onclick="openImportModal()" title="Bulk import channels via Content IDs, text lists, or M3U files">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                  <span>Bulk Import</span>
                </button>

                <button class="btn btn-secondary btn-sm" onclick="openExportModal()" title="Export lineup as Content IDs, M3U8 playlist, or JSON backup">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                  <span>Export</span>
                </button>

                <button class="btn btn-primary btn-sm" onclick="openChannelModal()">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                  <span>Add Channel</span>
                </button>
              </div>
            </div>
          </div>

          <!-- Dynamic Category Filter Tabs -->
          <div id="categoryTabs" class="category-tabs">
            <!-- Populated dynamically -->
          </div>

          <!-- Grid View Container (Cinematic Posters) -->
          <div id="channelGrid" class="channel-grid">
            <!-- Channel cards populated dynamically -->
          </div>

          <!-- Table View Container -->
          <div id="channelTableContainer" class="table-container">
            <table id="channelTable" class="channel-table">
              <thead>
                <tr>
                  <th style="width: 60px;">Poster</th>
                  <th>Channel Name & Slug</th>
                  <th>Category</th>
                  <th>Fallback Sources</th>
                  <th style="text-align: right;">Actions</th>
                </tr>
              </thead>
              <tbody id="channelTableBody">
                <!-- Rows populated dynamically -->
              </tbody>
            </table>
          </div>
        </section>

        <!-- Dashboard Footer -->
        <footer class="dashboard-footer">
          <div class="footer-left">
            <div class="footer-logo">
              <svg width="15" height="15" viewBox="0 0 64 64" fill="none">
                <path d="M16 21 L26 32 L16 43" stroke="#FFFFFF" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.85"/>
                <path d="M29 18 C29 16.5 30.6 15.6 31.8 16.4 L50.2 30.4 C51.4 31.2 51.4 32.8 50.2 33.6 L31.8 47.6 C30.6 48.4 29 47.5 29 46 Z" fill="#FFFFFF"/>
              </svg>
            </div>
            <span class="footer-brand-name">ACEX<span style="color: var(--color-primary);">GATEWAY</span></span>
            <span class="footer-sep">•</span>
            <span class="footer-sub">STREAMFLIX CORE</span>
          </div>
          <div class="footer-right">
            <span>Stream Relay Gateway</span>
            <span class="footer-sep">•</span>
            <a href="javascript:void(0)" onclick="openUpdateModal()" style="color: var(--text-secondary); text-decoration: none;" title="Kiểm tra & Cập nhật hệ thống">v#{AcexGateway.version()}</a>
            <span class="footer-sep">•</span>
            <span>AceStream Protocol</span>
          </div>
        </footer>
      </div>

      <!-- Add / Edit Channel Modal -->
      <div id="channelModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'channelModal')">
        <div class="modal-window">
          <div class="modal-top">
            <h3 id="modalTitle">Add New Channel</h3>
            <button class="btn btn-secondary btn-xs" onclick="closeChannelModal()">✕</button>
          </div>
          <form onsubmit="handleSaveChannel(event)">
            <input type="hidden" id="editChannelId">
            <div class="form-group">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                <label class="form-label" style="margin-bottom: 0;">Channel Name:</label>
                <span id="autoDetectBadge" style="font-size: 11px; color: var(--color-success); font-weight: 600; display: none;">⚡ Tự động nhận diện</span>
              </div>
              <input type="text" id="inputName" class="form-control" placeholder="e.g., K+ Sport 1 HD, Sky Sports Premier League" required oninput="handleChannelNameInput(this.value)">
            </div>
            <div class="modal-grid-2col" style="display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md);">
              <div class="form-group">
                <label class="form-label">Category / Group:</label>
                <input type="text" id="inputGroup" class="form-control" placeholder="Sports, News, Movies...">
              </div>
              <div class="form-group">
                <label class="form-label">Country (e.g. VN, UK, US):</label>
                <input type="text" id="inputCountry" class="form-control" placeholder="VN, UK, US, ES...">
              </div>
            </div>

            <!-- Enhanced Interactive Sources Manager -->
            <div class="form-group">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                <label class="form-label" style="margin-bottom: 0;">AceStream Content IDs (Thứ tự ưu tiên #1 &rarr; #N):</label>
                <div style="display: flex; gap: 6px;">
                  <button type="button" class="btn btn-secondary btn-xs" onclick="pasteModalSourcesFromClipboard()" style="padding: 2px 8px; font-size: 11px;">
                    📋 Dán nhanh từ Clipboard
                  </button>
                  <button type="button" class="btn btn-secondary btn-xs" id="btnTestModalSources" onclick="testModalSources()" style="padding: 2px 8px; font-size: 11px;">
                    🔍 Kiểm tra nguồn
                  </button>
                </div>
              </div>

              <!-- Interactive Reorderable Sources List -->
              <div id="modalSourcesListContainer" style="margin-bottom: 6px; display: none; max-height: 160px; overflow-y: auto;">
                <!-- Populated dynamically via renderModalSourcesList() -->
              </div>

              <textarea id="inputSources" class="form-control" rows="3" placeholder="Nhập hoặc dán các Content ID (40 ký tự hex), hỗ trợ phân tách bằng dấu phẩy hoặc dòng mới" required oninput="handleSourcesTextareaInput(this.value)"></textarea>
              <div id="sourcesDetectedHint" class="form-hint" style="color: var(--color-success);"></div>
              <div id="modalValidationResults" style="margin-top: 6px; display: none;"></div>
            </div>
            <div class="form-group">
              <label class="form-label">Logo / Poster URL (Optional):</label>
              <input type="url" id="inputLogo" class="form-control" placeholder="https://example.com/logo.png">
            </div>
            <div style="display: flex; gap: var(--space-sm); justify-content: flex-end; margin-top: var(--space-lg);">
              <button type="button" class="btn btn-secondary" onclick="closeChannelModal()">Cancel</button>
              <button type="submit" class="btn btn-primary" id="saveChannelBtn">Save Channel</button>
            </div>
          </form>
        </div>
      </div>

      <!-- Bulk Import Channels Modal -->
      <div id="importModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'importModal')">
        <div class="modal-window" style="max-width: 680px;">
          <div class="modal-top">
            <div>
              <h3 style="display: flex; align-items: center; gap: 8px;">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <span>Bulk Import Channels</span>
              </h3>
              <p style="font-size: 13px; color: var(--text-secondary); margin-top: 4px;">
                Quickly import channels via AceStream Content IDs, playlist formats, or upload an M3U file.
              </p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeImportModal()">✕</button>
          </div>

          <!-- Import Method Tabs -->
          <div style="display: flex; gap: var(--space-xs); background: var(--surface-card); padding: 4px; border-radius: var(--radius-md); border: 1px solid var(--border-default); margin-bottom: var(--space-md);">
            <button id="importTabPasteBtn" type="button" class="btn btn-sm" style="flex: 1; background: var(--surface-modal); color: #fff;" onclick="switchImportTab('paste')">
              📋 Paste Text / Content IDs
            </button>
            <button id="importTabFileBtn" type="button" class="btn btn-sm btn-ghost" style="flex: 1; color: var(--text-secondary);" onclick="switchImportTab('file')">
              📁 Upload File (.m3u8, .m3u, .txt)
            </button>
          </div>

          <!-- Paste Tab Content -->
          <div id="importPasteSection">
            <div class="form-group">
              <label class="form-label" style="display: flex; justify-content: space-between;">
                <span>Content IDs or Playlist Data:</span>
                <span style="font-size: 12px; color: var(--text-tertiary);">Supports raw hashes, pipe format, acestream://, or M3U</span>
              </label>
              <textarea id="importTextContent" class="form-control" rows="6" style="font-family: var(--font-mono); font-size: 13px;" placeholder="Paste your channels here, for example:
    dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c | K+ Sport 1 HD | VN | Sports
    4a32e8b7c61f55a1234567890123456789012345 | Sky Sports Main Event | UK | Sports
    acestream://1111222233334444555566667777888899990000#DAZN 1
    or raw 40-character Content IDs (one per line)" oninput="debouncedImportPreview()"></textarea>
            </div>
          </div>

          <!-- File Upload Tab Content -->
          <div id="importFileSection" style="display: none;">
            <div class="form-group">
              <label class="form-label">Select Playlist / Content ID File:</label>
              <div style="border: 2px dashed var(--border-hover); border-radius: var(--radius-md); padding: 24px; text-align: center; background: var(--surface-card); cursor: pointer;" onclick="document.getElementById('importFileInput').click()">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--text-tertiary)" stroke-width="2" style="margin: 0 auto 8px;"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <div style="font-weight: 600; color: #FFFFFF; font-size: 14px;">Click to browse or drop file here</div>
                <div style="font-size: 12px; color: var(--text-tertiary); margin-top: 4px;">Accepts .m3u, .m3u8, .txt files</div>
                <input type="file" id="importFileInput" accept=".m3u,.m3u8,.txt" style="display: none;" onchange="handleImportFileSelect(event)">
              </div>
              <div id="importFileName" style="font-family: var(--font-mono); font-size: 12px; color: var(--color-success); margin-top: 6px; display: none;"></div>
            </div>
          </div>

          <!-- Options Grid -->
          <div class="modal-grid-3col" style="margin-bottom: var(--space-md);">
            <div class="form-group" style="margin-bottom: 0;">
              <label class="form-label" style="font-size: 12px;">Default Category:</label>
              <input type="text" id="importDefaultGroup" class="form-control" style="padding: 6px 10px; font-size: 13px;" placeholder="Sports, Live TV..." value="Sports" oninput="debouncedImportPreview()">
            </div>
            <div class="form-group" style="margin-bottom: 0;">
              <label class="form-label" style="font-size: 12px;">Default Country:</label>
              <input type="text" id="importDefaultCountry" class="form-control" style="padding: 6px 10px; font-size: 13px;" placeholder="VN, UK, US..." value="VN" oninput="debouncedImportPreview()">
            </div>
            <div class="form-group" style="margin-bottom: 0;">
              <label class="form-label" style="font-size: 12px;">Import Mode:</label>
              <select id="importMode" class="form-control" style="padding: 6px 10px; font-size: 13px;">
                <option value="merge" selected>Merge with Lineup</option>
                <option value="replace">Replace Entire Lineup</option>
              </select>
            </div>
          </div>

          <!-- Live Preview Container -->
          <div id="importPreviewBox" style="background: var(--surface-card); border: 1px solid var(--border-default); border-radius: var(--radius-md); padding: 12px; margin-bottom: var(--space-md); display: none;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
              <span id="importPreviewBadge" class="chip-status-success">✨ Found 0 Channels</span>
              <span style="font-size: 12px; color: var(--text-tertiary);">Live preview of detected channels:</span>
            </div>
            <div id="importPreviewList" style="max-height: 140px; overflow-y: auto; display: flex; flex-direction: column; gap: 4px; font-size: 13px;">
              <!-- Filled dynamically -->
            </div>
          </div>

          <!-- Modal Footer Actions -->
          <div style="display: flex; gap: var(--space-sm); justify-content: flex-end; align-items: center;">
            <button type="button" class="btn btn-secondary" onclick="closeImportModal()">Cancel</button>
            <button type="button" class="btn btn-primary" id="executeImportBtn" disabled onclick="executeChannelImport()">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg>
              <span id="executeImportBtnText">Import Channels</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Stream Launcher Modal -->
      <div id="launcherModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'launcherModal')">
        <div class="modal-window" style="max-width: 580px;">
          <div class="modal-top">
            <div>
              <h3 id="launcherModalTitle">Launch Live Stream</h3>
              <p id="launcherModalSubtitle" style="font-size: 13px; color: var(--text-secondary); margin-top: 4px;">Play directly in your media player or copy stream URL</p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeLauncherModal()">✕</button>
          </div>

          <div style="margin-bottom: var(--space-md);">
            <label class="form-label">Direct MPEG-TS Stream URL:</label>
            <div class="input-row">
              <input type="text" id="launcherStreamUrl" class="text-input-styled" readonly>
              <button class="btn btn-primary btn-sm" onclick="copyLauncherUrl(this)">Copy</button>
            </div>
          </div>

          <label class="form-label">Open in Media Player:</label>
          <div class="launcher-links-grid" style="margin-bottom: var(--space-md);">
            <a id="launchVlc" href="#" class="app-launch-card">
              <div style="font-size: 24px;">🟧</div>
              <div>
                <div style="font-weight: 700; font-size: 14px; color: #FFFFFF;">VLC Media Player</div>
                <div style="font-size: 12px; color: var(--text-tertiary);">vlc:// protocol (All OS)</div>
              </div>
            </a>

            <a id="launchIina" href="#" class="app-launch-card">
              <div style="font-size: 24px;">🎬</div>
              <div>
                <div style="font-weight: 700; font-size: 14px; color: #FFFFFF;">IINA Player</div>
                <div style="font-size: 12px; color: var(--text-tertiary);">iina:// protocol (Mac)</div>
              </div>
            </a>

            <a id="launchPot" href="#" class="app-launch-card">
              <div style="font-size: 24px;">⚡</div>
              <div>
                <div style="font-weight: 700; font-size: 14px; color: #FFFFFF;">PotPlayer</div>
                <div style="font-size: 12px; color: var(--text-tertiary);">potplayer:// protocol (Win)</div>
              </div>
            </a>

            <a id="launchBrowser" href="#" target="_blank" class="app-launch-card">
              <div style="font-size: 24px;">🌐</div>
              <div>
                <div style="font-weight: 700; font-size: 14px; color: #FFFFFF;">Raw Stream</div>
                <div style="font-size: 12px; color: var(--text-tertiary);">Open stream link</div>
              </div>
            </a>
          </div>

          <div style="background: rgba(255,255,255,0.03); border: 1px solid var(--border-subtle); border-radius: var(--radius-sm); padding: 12px;">
            <div style="font-size: 12px; color: var(--text-secondary); line-height: 1.5;">
              💡 <strong>Pro Tip:</strong> Dedicated players like VLC, IINA, or PotPlayer handle P2P jitter and dropped packets natively, ensuring buttery-smooth playback with 0% CPU overhead.
            </div>
          </div>
        </div>
      </div>

      <!-- In-Dashboard Web Video Player Modal (MPEG-TS Live Player) -->
      <div id="webPlayerModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'webPlayerModal')">
        <div class="modal-window" style="max-width: 820px; padding: var(--space-md);">
          <div class="modal-top" style="margin-bottom: var(--space-sm);">
            <div>
              <h3 id="webPlayerTitle" style="display: flex; align-items: center; gap: 8px;">
                <span style="color: var(--color-primary);">▶</span>
                <span id="webPlayerChannelName">Live Stream Player</span>
              </h3>
              <p style="font-size: 12px; color: var(--text-secondary); margin-top: 2px;">
                Phát trực tiếp chuẩn MPEG-TS ngay trong trình duyệt (HTML5 MSE)
              </p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeWebPlayerModal()">✕</button>
          </div>

          <div class="video-player-box">
            <div class="video-player-hud">
              <span id="playerLiveBadge" class="chip-status-success" style="font-size: 11px;">● LIVE</span>
              <span id="playerStatsBadge" style="font-family: var(--font-mono); font-size: 11px; background: rgba(0,0,0,0.6); padding: 2px 8px; border-radius: 4px; color: var(--text-secondary);">MPEG-TS Engine</span>
            </div>
            <video id="webVideoPlayer" controls autoplay muted playsinline></video>
          </div>

          <div style="display: flex; justify-content: space-between; align-items: center; margin-top: var(--space-sm); flex-wrap: wrap; gap: 8px;">
            <div style="font-size: 12px; color: var(--text-tertiary);">
              💡 <em>Lưu ý:</em> Nhấn bỏ Mute trên thanh video để nghe âm thanh. Nếu trình duyệt không tương thích với audio codec, hãy sử dụng nút mở VLC/IINA ngoài.
            </div>
            <div style="display: flex; gap: 6px;">
              <button class="btn btn-secondary btn-sm" onclick="openExternalFromWebPlayer()">
                <span>Mở trong Desktop App</span>
              </button>
              <button class="btn btn-primary btn-sm" onclick="closeWebPlayerModal()">
                <span>Đóng Player</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- QR Code Modal -->
      <div id="qrModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'qrModal')">
        <div class="modal-window" style="max-width: 440px;">
          <div class="modal-top">
            <h3>Scan Playlist QR Code</h3>
            <button class="btn btn-secondary btn-xs" onclick="closeQrModal()">✕</button>
          </div>
          <div class="qr-card-box">
            <div class="qr-img-wrap">
              <img id="qrImageElement" src="" alt="M3U8 QR Code">
            </div>
            <p style="font-size: 14px; color: var(--text-secondary); line-height: 1.5;">
              Open your camera app on your phone or Smart TV to automatically import the M3U8 playlist.
            </p>
            <div id="qrM3uDisplay" style="width: 100%; background: #0A0A0A; border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 10px; font-family: var(--font-mono); font-size: 13px; color: var(--color-primary); word-break: break-all;">
              #{m3u_display_url}
            </div>
          </div>
        </div>
      </div>

      <!-- Xtream Codes Modal -->
      <div id="xtreamModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'xtreamModal')">
        <div class="modal-window" style="max-width: 540px;">
          <div class="modal-top">
            <div style="display: flex; align-items: center; gap: 10px;">
              <div class="panel-icon-wrap" style="width: 36px; height: 36px;">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2"><path d="M4 11a9 9 0 0 1 9 9"/><path d="M4 4a16 16 0 0 1 16 16"/><circle cx="5" cy="19" r="1"/></svg>
              </div>
              <div>
                <h3 style="font-size: 20px; font-weight: 700; color: #fff;">Xtream Codes Login & Auth</h3>
                <p style="font-size: 13px; color: var(--text-secondary); margin-top: 2px;">For TiviMate, IPTV Smarters, XCIPTV & Smart TVs</p>
              </div>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeXtreamModal()">✕</button>
          </div>

          <div style="display: flex; flex-direction: column; gap: 13px; margin-top: 14px;">
            <!-- Authentication Status Card with Toggle -->
            <div style="background: rgba(255,255,255,0.03); border: 1px solid var(--border-subtle); border-radius: var(--radius-sm); padding: 12px 14px; display: flex; align-items: center; justify-content: space-between;">
              <div>
                <div style="font-size: 13px; font-weight: 600; color: #fff; display: flex; align-items: center; gap: 8px;">
                  <span>Authentication</span>
                  <span id="authStatusBadge" class="badge-status #{if auth_enabled, do: "badge-enabled", else: "badge-disabled"}">
                    #{if auth_enabled, do: "ENABLED", else: "DISABLED (OPEN)"}
                  </span>
                </div>
                <p style="font-size: 12px; color: var(--text-secondary); margin-top: 2px;">
                  Enforce username & password for stream access & Xtream API
                </p>
              </div>
              <label class="switch" title="Toggle Authentication">
                <input type="checkbox" id="authToggleInput" #{if auth_enabled, do: "checked", else: ""} onchange="onAuthToggleChange()">
                <span class="slider"></span>
              </label>
            </div>

            <!-- Server URL -->
            <div>
              <label class="form-label" style="font-size: 12px;">Server URL / Host:</label>
              <div class="input-row">
                <input type="text" id="xtreamServerInput" class="text-input-styled" readonly value="#{base_url}">
                <button class="btn btn-primary btn-sm" onclick="copyInput('xtreamServerInput', 'Server URL copied!', this)">Copy</button>
              </div>
            </div>

            <!-- Port -->
            <div>
              <label class="form-label" style="font-size: 12px;">Port:</label>
              <div class="input-row">
                <input type="text" id="xtreamPortInput" class="text-input-styled" readonly value="#{server_port}">
                <button class="btn btn-secondary btn-sm" onclick="copyInput('xtreamPortInput', 'Port copied!', this)">Copy</button>
              </div>
            </div>

            <!-- Username -->
            <div>
              <label class="form-label" style="font-size: 12px;">Username:</label>
              <div class="input-row">
                <input type="text" id="xtreamUserInput" class="text-input-styled" value="#{auth_user}" placeholder="e.g. admin">
                <button class="btn btn-secondary btn-sm" onclick="copyInput('xtreamUserInput', 'Username copied!', this)">Copy</button>
              </div>
            </div>

            <!-- Password -->
            <div>
              <label class="form-label" style="font-size: 12px;">Password:</label>
              <div class="input-row">
                <input type="text" id="xtreamPassInput" class="text-input-styled" value="#{auth_pass}" placeholder="e.g. acex123">
                <button type="button" class="btn btn-secondary btn-sm" onclick="generateRandomPass()" title="Generate Random Password">🎲 Random</button>
                <button class="btn btn-secondary btn-sm" onclick="copyInput('xtreamPassInput', 'Password copied!', this)">Copy</button>
              </div>
            </div>

            <!-- EPG URL -->
            <div>
              <label class="form-label" style="font-size: 12px;">EPG URL (XMLTV):</label>
              <div class="input-row">
                <input type="text" id="xtreamEpgInput" class="text-input-styled" value="#{epg_url}" placeholder="https://example.com/epg.xml">
                <button class="btn btn-secondary btn-sm" onclick="copyInput('xtreamEpgInput', 'EPG URL copied!', this)">Copy</button>
              </div>
            </div>

            <!-- Save Credentials Button -->
            <button id="saveXtreamBtn" class="btn btn-primary btn-md" style="width: 100%; justify-content: center; margin-top: 4px;" onclick="saveXtreamSettings()">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>
              <span>Save Credentials</span>
            </button>

            <div style="background: rgba(255,255,255,0.03); border: 1px solid var(--border-subtle); border-radius: var(--radius-sm); padding: 12px; margin-top: 2px;">
              <div style="font-size: 12px; color: var(--text-secondary); line-height: 1.5;">
                💡 <strong>Tip:</strong> In your Smart TV IPTV app, choose <em>Add Playlist</em> &rarr; <em>Xtream Codes API</em>, and paste the parameters above. Saved credentials apply immediately without server restarts.
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Export Channels Modal -->
      <div id="exportModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'exportModal')">
        <div class="modal-window" style="max-width: 640px;">
          <div class="modal-top">
            <div>
              <h3 style="display: flex; align-items: center; gap: 8px;">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                <span>Export Channels Lineup</span>
              </h3>
              <p style="font-size: 13px; color: var(--text-secondary); margin-top: 4px;">
                Download or copy your channel catalog in standard formats:
              </p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeExportModal()">✕</button>
          </div>

          <!-- Format Choice Grid -->
          <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: var(--space-sm); margin-bottom: var(--space-md);">
            <!-- Format 1: Text Content IDs -->
            <a href="/api/channels/export?format=txt" download="acex_channels.txt" class="btn btn-secondary" style="flex-direction: column; padding: 14px 10px; gap: 4px; text-decoration: none; text-align: center;">
              <span style="font-size: 20px;">📄</span>
              <span style="font-weight: 700; color: #fff; font-size: 13px;">Content IDs (.txt)</span>
              <span style="font-size: 11px; color: var(--text-tertiary);">Pipe format list</span>
            </a>

            <!-- Format 2: M3U8 Playlist -->
            <a href="/api/channels/export?format=m3u8" download="acex_playlist.m3u8" class="btn btn-secondary" style="flex-direction: column; padding: 14px 10px; gap: 4px; text-decoration: none; text-align: center;">
              <span style="font-size: 20px;">📺</span>
              <span style="font-weight: 700; color: #fff; font-size: 13px;">IPTV Playlist (.m3u8)</span>
              <span style="font-size: 11px; color: var(--text-tertiary);">For IPTV players</span>
            </a>

            <!-- Format 3: JSON Full Backup -->
            <a href="/api/channels/export?format=json" download="acex_channels.json" class="btn btn-secondary" style="flex-direction: column; padding: 14px 10px; gap: 4px; text-decoration: none; text-align: center;">
              <span style="font-size: 20px;">💾</span>
              <span style="font-weight: 700; color: #fff; font-size: 13px;">JSON Backup (.json)</span>
              <span style="font-size: 11px; color: var(--text-tertiary);">Full channel config</span>
            </a>
          </div>

          <!-- Quick Text Preview & Copy Area -->
          <div class="form-group">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
              <label class="form-label" style="margin-bottom: 0;">Content IDs Preview (Clean format):</label>
              <button class="btn btn-secondary btn-xs" onclick="copyExportText(this)">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                <span>Copy All</span>
              </button>
            </div>
            <textarea id="exportPreviewText" class="form-control" rows="8" readonly style="font-family: var(--font-mono); font-size: 12px; line-height: 1.5; color: var(--text-secondary);"></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; margin-top: var(--space-md);">
            <button class="btn btn-secondary" onclick="closeExportModal()">Close</button>
          </div>
        </div>
      </div>

      <!-- System Update Modal (1-Click Updater) -->
      <div id="updateModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'updateModal')">
        <div class="modal-window" style="max-width: 580px;">
          <div class="modal-top">
            <div style="display: flex; align-items: center; gap: 10px;">
              <div class="panel-icon-wrap" style="width: 36px; height: 36px;">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2">
                  <path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/>
                </svg>
              </div>
              <div>
                <h3 style="font-size: 20px; font-weight: 700; color: #fff;">Cập Nhật Hệ Thống</h3>
                <p style="font-size: 13px; color: var(--text-secondary); margin-top: 2px;">Tự động kiểm tra và nâng cấp phiên bản mới nhất</p>
              </div>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeUpdateModal()">✕</button>
          </div>

          <div style="display: flex; flex-direction: column; gap: 14px; margin-top: 14px;">
            <!-- Version Comparison Banner -->
            <div style="background: rgba(255, 255, 255, 0.03); border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 14px; display: flex; align-items: center; justify-content: space-between;">
              <div>
                <div style="font-size: 11px; text-transform: uppercase; color: var(--text-tertiary); letter-spacing: 0.05em;">Phiên bản hiện tại</div>
                <div style="font-family: var(--font-mono); font-size: 16px; font-weight: 700; color: #FFFFFF; margin-top: 2px;" id="modalCurrentVer">v#{AcexGateway.version()}</div>
              </div>
              <div style="font-size: 20px; color: var(--text-tertiary);">➔</div>
              <div>
                <div style="font-size: 11px; text-transform: uppercase; color: var(--text-tertiary); letter-spacing: 0.05em;">Bản mới nhất</div>
                <div style="font-family: var(--font-mono); font-size: 16px; font-weight: 700; color: var(--color-primary);" id="modalLatestVer">Đang kiểm tra...</div>
              </div>
              <div id="modalUpdateBadgeStatus" style="padding: 4px 10px; border-radius: var(--radius-full); font-size: 12px; font-weight: 600; background: var(--border-default); color: var(--text-secondary);">
                Checking...
              </div>
            </div>

            <!-- Release Notes View -->
            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                <label class="form-label" style="font-size: 12px; margin-bottom: 0;">Ghi chú phát hành (Changelog):</label>
                <a id="modalReleaseLink" href="https://github.com/quaywin/acex/releases" target="_blank" rel="noopener noreferrer" style="font-size: 12px; color: var(--color-primary); text-decoration: none;">Xem trên GitHub ↗</a>
              </div>
              <div id="modalReleaseNotes" style="background: #0A0A0A; border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 12px; font-size: 13px; line-height: 1.5; color: var(--text-secondary); max-height: 180px; overflow-y: auto; white-space: pre-wrap; font-family: var(--font-mono);">Đang kiểm tra thông tin phiên bản từ GitHub...</div>
            </div>

            <!-- Update In-Progress Box (Hidden by default) -->
            <div id="updateProgressBox" style="display: none; background: rgba(225, 29, 72, 0.08); border: 1px solid var(--color-primary); border-radius: var(--radius-sm); padding: 14px; text-align: center;">
              <div style="font-size: 24px; margin-bottom: 6px;">🔄</div>
              <div style="font-weight: 700; color: #FFFFFF; font-size: 15px;" id="updateProgressText">Đang nâng cấp hệ thống...</div>
              <div style="font-size: 12px; color: var(--text-secondary); margin-top: 4px;">Dịch vụ đang kéo Image mới và khởi động lại. Trang sẽ tự tải lại khi hoàn tất.</div>
              <div style="margin-top: 10px; font-family: var(--font-mono); font-size: 12px; color: var(--color-primary);" id="updateCountdownTimer">Đang kết nối lại sau: 15s</div>
            </div>

            <!-- Fallback Terminal Command Box -->
            <div>
              <label class="form-label" style="font-size: 12px;">Lệnh cập nhật thủ công qua Terminal (Fallback):</label>
              <div class="input-row">
                <input type="text" id="manualUpdateCmdInput" class="text-input-styled" readonly value="docker compose pull && docker compose up -d">
                <button class="btn btn-secondary btn-sm" onclick="copyInput('manualUpdateCmdInput', 'Đã sao chép lệnh!', this)">Sao chép</button>
              </div>
            </div>

            <!-- Footer Actions -->
            <div style="display: flex; gap: var(--space-sm); justify-content: space-between; align-items: center; margin-top: 4px;">
              <button class="btn btn-secondary btn-sm" onclick="checkSystemVersion(true)">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
                <span>Kiểm tra lại</span>
              </button>
              <div style="display: flex; gap: var(--space-sm);">
                <button class="btn btn-secondary" onclick="closeUpdateModal()">Đóng</button>
                <button class="btn btn-primary" id="btnExecuteUpdate" onclick="executeSystemUpdate()">
                  ⚡ Cập nhật ngay (1-Click)
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Toast Shelf -->
      <div id="toastShelf" class="toast-shelf"></div>

      <script>
        let allChannels = #{channels_json};
        const baseUrl = "#{base_url}";
        let appSettings = #{Jason.encode!(%{auth_enabled: auth_enabled, auth_username: auth_user, auth_password: auth_pass, epg_url: epg_url})};
        let currentFilterGroup = "ALL";
        let currentFleetFilter = "all";
        let currentView = "grid";
        let activeStreamUrl = "";
        let mpegtsPlayerInstance = null;
        let activeWebPlayerUrl = "";
        let activeWebPlayerTitle = "";
        let modalSourcesArray = [];
        let isManuallyEditingGroup = false;
        let isManuallyEditingCountry = false;

        function getLiveStreamUrl(target) {
          if (appSettings && appSettings.auth_enabled && appSettings.auth_username && appSettings.auth_password) {
            return baseUrl + "/live/" + encodeURIComponent(appSettings.auth_username) + "/" + encodeURIComponent(appSettings.auth_password) + "/" + encodeURIComponent(target) + ".ts";
          } else {
            return baseUrl + "/live?channel=" + encodeURIComponent(target);
          }
        }

        function getQuickStreamUrl(target) {
          if (appSettings && appSettings.auth_enabled && appSettings.auth_username && appSettings.auth_password) {
            return baseUrl + "/live/" + encodeURIComponent(appSettings.auth_username) + "/" + encodeURIComponent(appSettings.auth_password) + "/" + encodeURIComponent(target) + ".ts";
          } else {
            return baseUrl + "/live?id=" + encodeURIComponent(target);
          }
        }

        function openWebPlayerForChannel(channelId) {
          const c = (allChannels || []).find(x => x.id === channelId);
          const name = c ? (c.name || "Channel") : "Channel";
          const liveUrl = getLiveStreamUrl(channelId);
          openWebPlayerModal(name, liveUrl);
        }

        function openLauncherForChannel(channelId) {
          const c = (allChannels || []).find(x => x.id === channelId);
          const name = c ? (c.name || "Channel") : "Channel";
          const liveUrl = getLiveStreamUrl(channelId);
          openLauncherModal(name, liveUrl);
        }

        // DOM Elements
        const channelGrid = document.getElementById("channelGrid");
        const channelTableContainer = document.getElementById("channelTableContainer");
        const channelTable = document.getElementById("channelTable");
        const channelTableBody = document.getElementById("channelTableBody");
        const categoryTabs = document.getElementById("categoryTabs");
        const channelCountBadge = document.getElementById("channelCountBadge");

        // Render Category Tabs (StreamFlix Filter Chips)
        function renderCategoryTabs() {
          const groups = new Set();
          allChannels.forEach(c => {
            if (c.group && c.group.trim()) groups.add(c.group.trim());
          });

          const groupList = ["ALL", ...Array.from(groups).sort()];
          categoryTabs.innerHTML = groupList.map(g => {
            const count = g === "ALL" ? allChannels.length : allChannels.filter(c => c.group === g).length;
            const label = g === "ALL" ? "All" : g;
            const activeClass = currentFilterGroup === g ? "active" : "";
            return `
              <button class="tab-btn ${activeClass}" onclick="selectCategory('${g}')">
                <span>${label}</span>
                <span style="opacity: 0.7; font-size: 12px;">(${count})</span>
              </button>
            `;
          }).join("");
        }

        function selectCategory(group) {
          currentFilterGroup = group;
          renderCategoryTabs();
          filterChannels();
        }

        function switchView(mode) {
          currentView = mode;
          document.getElementById("viewGridBtn").className = "view-btn " + (mode === "grid" ? "active" : "");
          document.getElementById("viewListBtn").className = "view-btn " + (mode === "list" ? "active" : "");
          filterChannels();
        }

        // Render Channel Catalog
        function renderChannels(channels = null) {
          const list = Array.isArray(channels) ? channels : (allChannels || []);
          channelCountBadge.innerText = list.length + " channels";

          if (list.length === 0) {
            const emptyHtml = `
              <div style="grid-column: 1/-1; text-align: center; padding: 48px 24px; background: var(--surface-card); border-radius: var(--radius-md); border: 1px dashed var(--border-default);">
                <div style="font-size: 32px; margin-bottom: 8px;">📡</div>
                <h4 style="font-family: var(--font-headline); font-size: 20px; color: #FFFFFF; margin-bottom: 6px;">No channels found</h4>
                <p style="color: var(--text-secondary); font-size: 14px;">Try searching with different keywords or click '+ Add Channel' to create one.</p>
              </div>
            `;
            channelGrid.innerHTML = emptyHtml;
            channelGrid.style.display = "grid";
            if (channelTableContainer) channelTableContainer.classList.remove("show");
            return;
          }

          if (currentView === "grid") {
            channelGrid.style.display = "grid";
            if (channelTableContainer) channelTableContainer.classList.remove("show");

            channelGrid.innerHTML = list.map(c => {
              const sources = c.sources || [];
              const fallbackCount = sources.length;
              const liveUrl = getLiveStreamUrl(c.id);
              const initials = (c.name || "TV").substring(0, 2).toUpperCase();

              const sourcesListHtml = sources.map((s, idx) => `
                <div class="source-item" id="source-row-${c.id}-${idx}">
                  <span style="color: var(--color-primary); font-weight: 700;">#${idx + 1}</span>
                  <span style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${s}</span>
                  <span id="badge-${c.id}-${idx}" style="font-size: 11px;"></span>
                  <button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); copyText('${s}', 'Source hash copied!', this)">Copy</button>
                </div>
              `).join("");

              return `
                <div class="channel-card-sf" data-id="${c.id}">
                  <!-- 16:9 Cinematic Poster Header -->
                  <div class="poster-box">
                    ${c.logo ? `
                      <img class="poster-img" src="${c.logo}" alt="${c.name}" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex'">
                      <div class="poster-fallback" style="display: none;">${initials}</div>
                    ` : `
                      <div class="poster-fallback">${initials}</div>
                    `}
                    <div class="poster-scrim"></div>

                    <!-- Overlay Badges -->
                    <div class="poster-badges-top">
                      ${c.country ? `<span class="chip-filter" style="background: rgba(225, 29, 72, 0.25); border-color: rgba(225, 29, 72, 0.5); color: #FFF; font-weight: 700;">🌐 ${c.country}</span>` : ''}
                      <span class="chip-filter">${c.group || 'General'}</span>
                      <span class="chip-status-success">🛡️ ${fallbackCount} sources</span>
                    </div>

                    <!-- Centered Hover Play CTA (Primary Red) -->
                    <button class="poster-play-btn" onclick="openLauncherForChannel('${c.id}')" title="Play">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                    </button>
                  </div>

                  <!-- Content & Meta Area -->
                  <div class="card-content">
                    <div class="card-head">
                      <h4 class="card-title" title="${c.name}">${c.name}</h4>
                    </div>
                    <div class="card-slug">${c.id}</div>

                    <!-- Collapsible Sources Accordion -->
                    <div class="sources-accordion">
                      <div class="sources-toggle" onclick="toggleSourcesAccordion('${c.id}')">
                        <span>Fallback Sources (${fallbackCount})</span>
                        <span id="arrow-${c.id}">▼</span>
                      </div>
                      <div id="sources-${c.id}" class="sources-list">
                        <div style="display: flex; justify-content: flex-end; gap: 6px; padding: 4px 6px; border-bottom: 1px solid var(--border-subtle); margin-bottom: 4px;">
                          <button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); validateChannelSources('${c.id}')" title="Kiểm tra trạng thái nguồn" style="font-size: 10px; padding: 2px 6px;">🔍 Kiểm tra</button>
                          ${fallbackCount > 1 ? `<button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); pruneDeadSources('${c.id}')" title="Dọn dẹp nguồn chết" style="font-size: 10px; padding: 2px 6px; color: var(--color-danger);">🧹 Dọn nguồn chết</button>` : ''}
                        </div>
                        ${sourcesListHtml}
                      </div>
                    </div>

                    <!-- Card Actions Row -->
                    <div class="card-actions-row">
                      <button class="btn btn-secondary btn-sm" onclick="openWebPlayerForChannel('${c.id}')" title="Xem trực tiếp trên trình duyệt">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                        <span>▶ Xem thử</span>
                      </button>
                      <button class="btn btn-primary btn-sm" onclick="openLauncherForChannel('${c.id}')">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                        <span>Watch</span>
                      </button>

                      <div class="card-icon-actions">
                        <button class="btn btn-ghost btn-icon btn-sm" onclick="copyText('${liveUrl}', 'Stream link copied!', this)" title="Copy stream link">
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                        </button>
                        <button class="btn btn-ghost btn-icon btn-sm" onclick="editChannel('${c.id}')" title="Edit channel">
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                        </button>
                        <button class="btn btn-destructive btn-icon btn-sm" onclick="deleteChannel('${c.id}')" title="Delete channel">
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              `;
            }).join("");
          } else {
            channelGrid.style.display = "none";
            if (channelTableContainer) channelTableContainer.classList.add("show");

            channelTableBody.innerHTML = list.map(c => {
              const liveUrl = getLiveStreamUrl(c.id);
              const initials = (c.name || "TV").substring(0, 2).toUpperCase();
              return `
                <tr data-id="${c.id}">
                  <td>
                    <div class="table-thumb">
                      ${c.logo ? `
                        <img src="${c.logo}" alt="${c.name}" style="width: 100%; height: 100%; object-fit: cover; border-radius: 4px;" onerror="this.outerHTML='<span>${initials}</span>'">
                      ` : `
                        <span>${initials}</span>
                      `}
                    </div>
                  </td>
                  <td>
                    <div style="display: flex; align-items: center; gap: 6px;">
                      <span style="font-weight: 700; color: #FFFFFF; font-size: 15px;">${c.name}</span>
                      ${c.country ? `<span class="chip-filter" style="font-size: 11px; padding: 1px 6px; font-weight: 700;">${c.country}</span>` : ''}
                    </div>
                    <div style="font-family: var(--font-mono); font-size: 12px; color: var(--text-tertiary);">${c.id}</div>
                  </td>
                  <td><span class="chip-filter">${c.group || 'General'}</span></td>
                  <td>
                    <div style="display: flex; align-items: center; gap: 4px;">
                      <span class="chip-status-success">🛡️ ${(c.sources || []).length} sources</span>
                      ${(c.sources || []).length > 1 ? `<button class="btn btn-ghost btn-xs" onclick="pruneDeadSources('${c.id}')" title="Dọn dẹp nguồn chết" style="padding: 1px 4px; font-size: 11px; color: var(--color-danger);">🧹</button>` : ''}
                    </div>
                  </td>
                  <td style="text-align: right;">
                    <div style="display: inline-flex; gap: 6px;">
                      <button class="btn btn-secondary btn-xs" onclick="openWebPlayerForChannel('${c.id}')" title="Xem trên trình duyệt">▶ Xem</button>
                      <button class="btn btn-primary btn-xs" onclick="openLauncherForChannel('${c.id}')">Watch</button>
                      <button class="btn btn-secondary btn-xs" onclick="copyText('${liveUrl}', 'Stream link copied!', this)">Link</button>
                      <button class="btn btn-secondary btn-xs" onclick="editChannel('${c.id}')">Edit</button>
                      <button class="btn btn-destructive btn-xs" onclick="deleteChannel('${c.id}')">Delete</button>
                    </div>
                  </td>
                </tr>
              `;
            }).join("");
          }
        }

        function toggleSourcesAccordion(id) {
          const list = document.getElementById("sources-" + id);
          const arrow = document.getElementById("arrow-" + id);
          if (list) {
            list.classList.toggle("show");
            if (arrow) arrow.innerText = list.classList.contains("show") ? "▲" : "▼";
          }
        }

        let activeStreamingChannelKeys = new Set();

        function setFleetFilter(filter) {
          currentFleetFilter = filter;
          ["all", "live", "multi", "single"].forEach(f => {
            const pill = document.getElementById("filterPill" + f.charAt(0).toUpperCase() + f.slice(1));
            if (pill) {
              if (f === filter) pill.classList.add("active");
              else pill.classList.remove("active");
            }
          });
          filterChannels();
        }

        function updateFleetHealthMetrics(activeKeys = null) {
          if (activeKeys) activeStreamingChannelKeys = activeKeys;
          const total = allChannels.length;
          const multi = allChannels.filter(c => (c.sources || []).length > 1).length;
          const single = allChannels.filter(c => (c.sources || []).length <= 1).length;

          let liveCount = 0;
          allChannels.forEach(c => {
            const isLive = activeStreamingChannelKeys.has(c.id) || (c.sources || []).some(s => activeStreamingChannelKeys.has(s));
            if (isLive) liveCount++;
          });

          const elTotal = document.getElementById("metricTotalChannels");
          if (elTotal) elTotal.innerText = total;
          const elMulti = document.getElementById("metricMultiSource");
          if (elMulti) elMulti.innerText = multi;
          const elSingle = document.getElementById("metricSingleSource");
          if (elSingle) elSingle.innerText = single;
          const elLive = document.getElementById("metricActiveStreams");
          if (elLive) elLive.innerText = liveCount;

          const pillAll = document.getElementById("countPillAll");
          if (pillAll) pillAll.innerText = total;
          const pillLive = document.getElementById("countPillLive");
          if (pillLive) pillLive.innerText = liveCount;
          const pillMulti = document.getElementById("countPillMulti");
          if (pillMulti) pillMulti.innerText = multi;
          const pillSingle = document.getElementById("countPillSingle");
          if (pillSingle) pillSingle.innerText = single;
        }

        function filterChannels() {
          const q = document.getElementById("channelSearch").value.toLowerCase().trim();
          let filtered = allChannels;

          if (currentFilterGroup !== "ALL") {
            filtered = filtered.filter(c => c.group === currentFilterGroup);
          }

          if (currentFleetFilter === "multi") {
            filtered = filtered.filter(c => (c.sources || []).length > 1);
          } else if (currentFleetFilter === "single") {
            filtered = filtered.filter(c => (c.sources || []).length <= 1);
          } else if (currentFleetFilter === "live") {
            filtered = filtered.filter(c =>
              activeStreamingChannelKeys.has(c.id) || (c.sources || []).some(s => activeStreamingChannelKeys.has(s))
            );
          }

          if (q) {
            filtered = filtered.filter(c =>
              c.name.toLowerCase().includes(q) ||
              (c.country && c.country.toLowerCase().includes(q)) ||
              (c.group && c.group.toLowerCase().includes(q)) ||
              c.id.toLowerCase().includes(q) ||
              (c.sources || []).some(s => s.toLowerCase().includes(q))
            );
          }

          renderChannels(filtered);
        }

        async function pruneAllDeadSources(btn = null) {
          if (!confirm("Hệ thống sẽ kiểm tra và loại bỏ các nguồn chết trên toàn bộ các kênh đa nguồn (kênh 1 nguồn luôn được bảo vệ an toàn). Tiếp tục?")) {
            return;
          }
          const origText = btn ? btn.innerHTML : "";
          if (btn) {
            btn.disabled = true;
            btn.innerHTML = "<span>⏳ Đang quét toàn bộ...</span>";
          }
          showToast("Đang quét và dọn nguồn chết toàn bộ hệ thống...", true);

          try {
            const resp = await fetch("/api/channels/prune-all-dead", {
              method: "POST",
              headers: { "Content-Type": "application/json" }
            });
            const data = await resp.json();
            if (resp.ok && data.status === "ok") {
              if (Array.isArray(data.channels)) {
                allChannels = data.channels;
                renderCategoryTabs();
                updateFleetHealthMetrics();
                filterChannels();
              }
              showToast("Hoàn tất dọn dẹp: Đã loại bỏ " + (data.pruned_sources_count || 0) + " nguồn chết!", true);
            } else {
              showToast(data.error || "Không thể dọn dẹp nguồn chết toàn bộ.", false);
            }
          } catch (err) {
            showToast("Lỗi kết nối khi dọn dẹp: " + err.message, false);
          } finally {
            if (btn) {
              btn.disabled = false;
              btn.innerHTML = origText;
            }
          }
        }

        // Clean dirty AceStream hash
        function extractCleanHash(str) {
          if (!str) return null;
          const match = str.match(/([a-fA-F0-9]{40})/);
          return match ? match[1].toLowerCase() : null;
        }

        function handleQuickInput(val) {
          const clean = extractCleanHash(val);
          const box = document.getElementById("quickDetectedBox");
          const text = document.getElementById("quickDetectedText");
          if (clean) {
            box.style.display = "inline-flex";
            text.innerText = "Clean hash detected: " + clean;
          } else {
            box.style.display = "none";
          }
        }

        function launchQuickStream() {
          const val = document.getElementById("quickTestInput").value.trim();
          const clean = extractCleanHash(val);
          if (!clean) {
            showToast("Please enter a valid Content ID (40 hex chars)", false);
            return;
          }
          const streamUrl = getQuickStreamUrl(clean);
          openLauncherModal("Quick Stream (" + clean.substring(0, 8) + "...)", streamUrl);
        }

        function copyQuickStreamUrl(btn = null) {
          const val = document.getElementById("quickTestInput").value.trim();
          const clean = extractCleanHash(val);
          if (!clean) {
            showToast("Please enter a valid Content ID to copy link!", false);
            return;
          }
          const url = getQuickStreamUrl(clean);
          copyText(url, "Link copied: " + url, btn);
        }

        function fillAddModalWithQuick() {
          const val = document.getElementById("quickTestInput").value.trim();
          const clean = extractCleanHash(val);
          openChannelModal();
          if (clean) {
            modalSourcesArray = [clean];
            renderModalSourcesList(true);
          }
        }

        function handleChannelNameInput(val) {
          const v = (val || "").trim();
          const badge = document.getElementById("autoDetectBadge");
          if (!v) {
            if (badge) badge.style.display = "none";
            return;
          }

          let detectedCountry = null;
          let detectedGroup = null;

          // Country heuristics
          if (/\b(vtv|htv|thvl|k\+|vtc|fpt|vieon|todaytv|truyenhinh|viet)\b/i.test(v)) {
            detectedCountry = "VN";
          } else if (/\b(sky|bbc|itv|tnt|channel 4|channel 5|bt sport)\b/i.test(v)) {
            detectedCountry = "UK";
          } else if (/\b(espn|nbc|cbs|hbo|fox|discovery|abc|cnn|paramount)\b/i.test(v)) {
            detectedCountry = "US";
          } else if (/\b(movistar|laliga|dazn|gol)\b/i.test(v)) {
            detectedCountry = "ES";
          }

          // Category heuristics
          if (/\b(sport|sports|football|bóng đá|thể thao|golf|tennis|f1|racing|nba|premier|serie|bundesliga|ufc|boxing)\b/i.test(v)) {
            detectedGroup = "Sports";
          } else if (/\b(movie|movies|cinema|phim|cine|hbo|cinemax|film)\b/i.test(v)) {
            detectedGroup = "Movies";
          } else if (/\b(news|thời sự|tin tức|cnn|bbc news)\b/i.test(v)) {
            detectedGroup = "News";
          } else if (/\b(music|âm nhạc|mtv|nhạc)\b/i.test(v)) {
            detectedGroup = "Music";
          }

          const groupInput = document.getElementById("inputGroup");
          const countryInput = document.getElementById("inputCountry");
          let detectedNotes = [];

          if (detectedCountry && !isManuallyEditingCountry) {
            if (countryInput) countryInput.value = detectedCountry;
            detectedNotes.push("Country: " + detectedCountry);
          }
          if (detectedGroup && !isManuallyEditingGroup) {
            if (groupInput) groupInput.value = detectedGroup;
            detectedNotes.push("Group: " + detectedGroup);
          }

          if (badge) {
            if (detectedNotes.length > 0) {
              badge.innerText = "⚡ " + detectedNotes.join(" | ");
              badge.style.display = "inline";
            } else {
              badge.style.display = "none";
            }
          }
        }

        function syncModalSourcesToTextarea() {
          const textarea = document.getElementById("inputSources");
          if (textarea) {
            textarea.value = modalSourcesArray.join("\\n");
            validateSourcesInput(textarea.value);
          }
        }

        function handleSourcesTextareaInput(val) {
          const matches = (val.match(/[a-fA-F0-9]{40}/g) || []);
          modalSourcesArray = matches.map(s => s.toLowerCase());
          renderModalSourcesList(false);
          validateSourcesInput(val);
        }

        function renderModalSourcesList(syncTextarea = true) {
          const container = document.getElementById("modalSourcesListContainer");
          if (!container) return;

          if (modalSourcesArray.length === 0) {
            container.style.display = "none";
            container.innerHTML = "";
            if (syncTextarea) syncModalSourcesToTextarea();
            return;
          }

          container.style.display = "flex";
          container.style.flexDirection = "column";
          container.style.gap = "4px";

          container.innerHTML = modalSourcesArray.map((src, idx) => {
            const isPrimary = idx === 0;
            const rankLabel = isPrimary ? "#1 (Chính)" : ("#" + (idx + 1) + " (Dự phòng)");
            const shortHash = src.slice(0, 8) + "..." + src.slice(-6);
            const canUp = idx > 0;
            const canDown = idx < modalSourcesArray.length - 1;

            return `
              <div class="source-card-item">
                <span class="source-card-rank ${isPrimary ? 'rank-primary' : 'rank-backup'}">${rankLabel}</span>
                <span class="source-card-hash" title="${src}"><code>${shortHash}</code></span>
                <div class="source-card-actions">
                  <button type="button" class="source-card-btn" onclick="moveModalSourceUp(${idx})" ${canUp ? '' : 'disabled'} title="Tăng mức ưu tiên">▲</button>
                  <button type="button" class="source-card-btn" onclick="moveModalSourceDown(${idx})" ${canDown ? '' : 'disabled'} title="Giảm mức ưu tiên">▼</button>
                  <button type="button" class="source-card-btn btn-remove" onclick="removeModalSource(${idx})" title="Xóa nguồn này">✕</button>
                </div>
              </div>
            `;
          }).join("");

          if (syncTextarea) syncModalSourcesToTextarea();
        }

        function moveModalSourceUp(idx) {
          if (idx <= 0 || idx >= modalSourcesArray.length) return;
          const temp = modalSourcesArray[idx];
          modalSourcesArray[idx] = modalSourcesArray[idx - 1];
          modalSourcesArray[idx - 1] = temp;
          renderModalSourcesList(true);
        }

        function moveModalSourceDown(idx) {
          if (idx < 0 || idx >= modalSourcesArray.length - 1) return;
          const temp = modalSourcesArray[idx];
          modalSourcesArray[idx] = modalSourcesArray[idx + 1];
          modalSourcesArray[idx + 1] = temp;
          renderModalSourcesList(true);
        }

        function removeModalSource(idx) {
          if (idx < 0 || idx >= modalSourcesArray.length) return;
          modalSourcesArray.splice(idx, 1);
          renderModalSourcesList(true);
        }

        async function pasteModalSourcesFromClipboard() {
          try {
            if (!navigator.clipboard || !navigator.clipboard.readText) {
              showToast("Trình duyệt không hỗ trợ đọc clipboard tự động, vui lòng dán tay vào ô phía dưới.", false);
              return;
            }
            const text = await navigator.clipboard.readText();
            const matches = (text.match(/[a-fA-F0-9]{40}/g) || []);
            if (matches.length === 0) {
              showToast("Không tìm thấy Content ID (40 ký tự hex) nào trong clipboard!", false);
              return;
            }

            let addedCount = 0;
            matches.forEach(m => {
              const lower = m.toLowerCase();
              if (!modalSourcesArray.some(s => s.toLowerCase() === lower)) {
                modalSourcesArray.push(lower);
                addedCount++;
              }
            });

            renderModalSourcesList(true);
            showToast("Đã trích xuất & dán " + matches.length + " Content ID (" + addedCount + " nguồn mới) từ clipboard!", true);
          } catch (err) {
            showToast("Không thể đọc clipboard: " + err.message, false);
          }
        }

        function validateSourcesInput(val) {
          const matches = val.match(/[a-fA-F0-9]{40}/g) || [];
          const hint = document.getElementById("sourcesDetectedHint");
          if (matches.length > 0) {
            hint.innerText = "✓ Detected " + matches.length + " valid Content IDs (40-char hex)";
            hint.style.color = "var(--color-success)";
          } else if (val.trim()) {
            hint.innerText = "⚠ No valid 40-character hex string detected";
            hint.style.color = "var(--color-warning)";
          } else {
            hint.innerText = "";
          }
        }

        // Channel Modal Controls
        function openChannelModal(channel = null) {
          const modal = document.getElementById("channelModal");
          const title = document.getElementById("modalTitle");
          const autoBadge = document.getElementById("autoDetectBadge");
          if (autoBadge) autoBadge.style.display = "none";
          isManuallyEditingGroup = false;
          isManuallyEditingCountry = false;

          const groupInput = document.getElementById("inputGroup");
          const countryInput = document.getElementById("inputCountry");
          if (groupInput) {
            groupInput.oninput = () => { isManuallyEditingGroup = true; };
          }
          if (countryInput) {
            countryInput.oninput = () => { isManuallyEditingCountry = true; };
          }

          if (channel) {
            title.innerText = "Edit Channel: " + channel.name;
            document.getElementById("editChannelId").value = channel.id;
            document.getElementById("inputName").value = channel.name || "";
            document.getElementById("inputCountry").value = channel.country || "";
            document.getElementById("inputGroup").value = channel.group || "";
            document.getElementById("inputLogo").value = channel.logo || "";
            modalSourcesArray = Array.isArray(channel.sources) ? [...channel.sources] : [];
            isManuallyEditingGroup = !!channel.group;
            isManuallyEditingCountry = !!channel.country;
          } else {
            title.innerText = "Add New Channel";
            document.getElementById("editChannelId").value = "";
            document.getElementById("inputName").value = "";
            document.getElementById("inputCountry").value = "";
            document.getElementById("inputGroup").value = "";
            document.getElementById("inputLogo").value = "";
            modalSourcesArray = [];
          }

          renderModalSourcesList();
          syncModalSourcesToTextarea();

          const resBox = document.getElementById("modalValidationResults");
          if (resBox) { resBox.style.display = "none"; resBox.innerHTML = ""; }
          const testBtn = document.getElementById("btnTestModalSources");
          if (testBtn) { testBtn.disabled = false; testBtn.innerText = "🔍 Kiểm tra nguồn"; }

          modal.classList.add("active");
          document.getElementById("inputName").focus();
        }

        async function testModalSources() {
          const val = document.getElementById("inputSources").value;
          const matches = val.match(/[a-fA-F0-9]{40}/g) || [];
          const resBox = document.getElementById("modalValidationResults");
          const btn = document.getElementById("btnTestModalSources");
          if (matches.length === 0) {
            showToast("Vui lòng nhập ít nhất 1 Content ID (40 ký tự hex)!", false);
            return;
          }
          btn.disabled = true;
          btn.innerText = "⏳ Đang kiểm tra...";
          resBox.style.display = "block";
          resBox.innerHTML = '<div style="font-size: 12px; color: var(--text-secondary);"><span class="live-dot" style="animation: pulse 1s infinite;"></span> Đang kiểm tra ' + matches.length + ' nguồn qua AceStream Engine...</div>';

          const results = [];
          for (const src of matches) {
            try {
              const resp = await fetch("/api/channels/validate-source", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ source: src, force: true })
              });
              const data = await resp.json();
              if (data && data.result) {
                results.push(data.result);
              } else {
                results.push({ source: src, valid: false, error: data.error || "Lỗi kết nối" });
              }
            } catch (err) {
              results.push({ source: src, valid: false, error: err.message });
            }
          }

          btn.disabled = false;
          btn.innerText = "🔍 Kiểm tra nguồn";

          const deadCount = results.filter(r => !r.valid).length;
          let html = '<div style="background: var(--surface-card); border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 8px; font-size: 12px; max-height: 140px; overflow-y: auto;">';
          results.forEach((r, idx) => {
            const shortHash = r.source.slice(0, 8) + '...' + r.source.slice(-6);
            if (r.valid) {
              html += '<div style="display: flex; justify-content: space-between; align-items: center; padding: 2px 0; color: var(--color-success);">' +
                '<span>🟢 #' + (idx+1) + ' <code>' + shortHash + '</code></span>' +
                '<span style="font-size: 11px; opacity: 0.8;">Sống (' + (r.response_time_ms || 0) + 'ms)</span></div>';
            } else {
              html += '<div style="display: flex; justify-content: space-between; align-items: center; padding: 2px 0; color: var(--color-danger);">' +
                '<span>🔴 #' + (idx+1) + ' <code>' + shortHash + '</code></span>' +
                '<span style="font-size: 11px; opacity: 0.9;">' + (r.error || 'Chết') + '</span></div>';
            }
          });

          if (deadCount > 0 && matches.length > 1) {
            const deadHashesJson = JSON.stringify(results.filter(r => !r.valid).map(r => r.source)).replace(/"/g, '&quot;');
            html += '<div style="margin-top: 6px; padding-top: 6px; border-top: 1px solid var(--border-subtle); display: flex; justify-content: flex-end;">' +
              '<button type="button" class="btn btn-destructive btn-xs" onclick="stripDeadModalSources(' + deadHashesJson + ')" style="font-size: 11px; padding: 2px 8px;">🧹 Loại bỏ ' + deadCount + ' nguồn chết</button></div>';
          }
          html += '</div>';
          resBox.innerHTML = html;
        }

        function stripDeadModalSources(deadList) {
          if (!Array.isArray(deadList) || deadList.length === 0) return;
          const deadSet = new Set(deadList.map(s => s.toLowerCase()));
          modalSourcesArray = modalSourcesArray.filter(s => !deadSet.has(s.toLowerCase()));
          renderModalSourcesList(true);
          const resBox = document.getElementById("modalValidationResults");
          if (resBox) resBox.style.display = "none";
          showToast("Đã loại bỏ " + deadList.length + " nguồn chết khỏi danh sách!", true);
        }

        async function validateChannelSources(channelId) {
          const arrow = document.getElementById("arrow-" + channelId);
          const list = document.getElementById("sources-" + channelId);
          if (list && !list.classList.contains("show")) {
            list.classList.add("show");
            if (arrow) arrow.innerText = "▲";
          }
          showToast("Đang kiểm tra sức khỏe các nguồn...", true);

          try {
            const resp = await fetch("/api/channels/" + encodeURIComponent(channelId) + "/validate", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ force: true })
            });
            const data = await resp.json();
            if (data && data.report && data.report.results) {
              data.report.results.forEach((r, idx) => {
                const badge = document.getElementById("badge-" + channelId + "-" + idx);
                if (badge) {
                  if (r.valid) {
                    badge.innerHTML = '<span style="color: var(--color-success); font-weight: 600;">🟢 Sống (' + (r.response_time_ms || 0) + 'ms)</span>';
                  } else {
                    badge.innerHTML = '<span style="color: var(--color-danger); font-weight: 600;">🔴 Chết</span>';
                  }
                }
              });
              showToast("Kiểm tra xong: " + data.report.alive_count + " sống, " + data.report.dead_count + " chết.", data.report.dead_count === 0);
            }
          } catch (err) {
            showToast("Lỗi khi kiểm tra nguồn: " + err.message, false);
          }
        }

        async function pruneDeadSources(channelId) {
          const c = allChannels.find(x => x.id === channelId);
          const name = c ? c.name : channelId;
          if (!confirm("Bạn có chắc chắn muốn kiểm tra và dọn dẹp các nguồn chết của kênh '" + name + "'?")) return;

          showToast("Đang kiểm tra và dọn dẹp nguồn chết...", true);
          try {
            const resp = await fetch("/api/channels/" + encodeURIComponent(channelId) + "/prune-dead", {
              method: "POST",
              headers: { "Content-Type": "application/json" }
            });
            const data = await resp.json();
            if (resp.ok && data.status === "ok") {
              if (data.channel) {
                const idx = allChannels.findIndex(x => x.id === channelId);
                if (idx !== -1) allChannels[idx] = data.channel;
                updateFleetHealthMetrics();
                filterChannels();
              }
              showToast("Đã dọn dẹp " + data.pruned_count + " nguồn chết thành công!", true);
            } else {
              showToast(data.error || "Không thể dọn dẹp nguồn chết.", false);
            }
          } catch (err) {
            showToast("Lỗi dọn dẹp: " + err.message, false);
          }
        }

        function closeChannelModal() {
          document.getElementById("channelModal").classList.remove("active");
        }

        function editChannel(id) {
          const c = allChannels.find(x => x.id === id);
          if (c) openChannelModal(c);
        }

        async function handleSaveChannel(e) {
          e.preventDefault();
          const editId = document.getElementById("editChannelId").value;
          const name = document.getElementById("inputName").value.trim();
          const country = document.getElementById("inputCountry").value.trim();
          const group = document.getElementById("inputGroup").value.trim();
          const logo = document.getElementById("inputLogo").value.trim();
          const rawSources = document.getElementById("inputSources").value.trim();

          const matches = rawSources.match(/[a-fA-F0-9]{40}/g) || [];
          if (matches.length === 0) {
            showToast("Please enter at least 1 valid 40-character Content ID!", false);
            return;
          }

          const payload = {
            id: editId || undefined,
            name,
            country,
            group,
            logo,
            sources: matches
          };

          try {
            const res = await fetch("/api/channels", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(payload)
            });

            if (res.ok) {
              const data = await res.json();
              if (editId) {
                allChannels = allChannels.map(c => c.id === editId ? data.channel : c);
                showToast("Channel updated successfully!");
              } else {
                allChannels.push(data.channel);
                showToast("New channel created successfully!");
              }
              renderCategoryTabs();
              updateFleetHealthMetrics();
              filterChannels();
              closeChannelModal();
            } else {
              showToast("Failed to save channel", false);
            }
          } catch (_) {
            showToast("Server connection error", false);
          }
        }

        async function deleteChannel(id) {
          if (!confirm("Are you sure you want to delete this channel from the lineup?")) return;
          try {
            const res = await fetch("/api/channels/" + encodeURIComponent(id), { method: "DELETE" });
            if (res.ok) {
              allChannels = allChannels.filter(c => c.id !== id);
              renderCategoryTabs();
              updateFleetHealthMetrics();
              filterChannels();
              showToast("Channel deleted successfully!");
            }
          } catch (_) {
            showToast("Failed to delete channel", false);
          }
        }

        // Bulk Import Modal Controls & Logic
        let importPreviewTimeout = null;
        let detectedImportChannels = [];

        function openImportModal() {
          const modal = document.getElementById("importModal");
          modal.classList.add("active");
          switchImportTab('paste');
          setTimeout(() => {
            document.getElementById("importTextContent").focus();
          }, 100);
        }

        function closeImportModal() {
          document.getElementById("importModal").classList.remove("active");
        }

        function switchImportTab(tab) {
          const pasteBtn = document.getElementById("importTabPasteBtn");
          const fileBtn = document.getElementById("importTabFileBtn");
          const pasteSec = document.getElementById("importPasteSection");
          const fileSec = document.getElementById("importFileSection");

          if (tab === 'file') {
            pasteBtn.className = "btn btn-sm btn-ghost";
            pasteBtn.style.color = "var(--text-secondary)";
            pasteBtn.style.background = "transparent";

            fileBtn.className = "btn btn-sm";
            fileBtn.style.color = "#fff";
            fileBtn.style.background = "var(--surface-modal)";

            pasteSec.style.display = "none";
            fileSec.style.display = "block";
          } else {
            fileBtn.className = "btn btn-sm btn-ghost";
            fileBtn.style.color = "var(--text-secondary)";
            fileBtn.style.background = "transparent";

            pasteBtn.className = "btn btn-sm";
            pasteBtn.style.color = "#fff";
            pasteBtn.style.background = "var(--surface-modal)";

            fileSec.style.display = "none";
            pasteSec.style.display = "block";
          }
        }

        function handleImportFileSelect(e) {
          const file = e.target.files[0];
          if (!file) return;

          const fileNameLabel = document.getElementById("importFileName");
          fileNameLabel.innerText = "📄 Selected: " + file.name + " (" + Math.round(file.size / 1024) + " KB)";
          fileNameLabel.style.display = "block";

          const reader = new FileReader();
          reader.onload = function(evt) {
            document.getElementById("importTextContent").value = evt.target.result;
            debouncedImportPreview(true);
          };
          reader.readAsText(file);
        }

        function debouncedImportPreview(immediate = false) {
          if (importPreviewTimeout) clearTimeout(importPreviewTimeout);
          if (immediate) {
            fetchImportPreview();
          } else {
            importPreviewTimeout = setTimeout(fetchImportPreview, 300);
          }
        }

        async function fetchImportPreview() {
          const content = document.getElementById("importTextContent").value.trim();
          const default_group = document.getElementById("importDefaultGroup").value.trim() || "General";
          const default_country = document.getElementById("importDefaultCountry").value.trim() || "";
          const previewBox = document.getElementById("importPreviewBox");
          const previewBadge = document.getElementById("importPreviewBadge");
          const previewList = document.getElementById("importPreviewList");
          const btn = document.getElementById("executeImportBtn");
          const btnText = document.getElementById("executeImportBtnText");

          if (!content) {
            previewBox.style.display = "none";
            btn.disabled = true;
            btnText.innerText = "Import Channels";
            detectedImportChannels = [];
            return;
          }

          try {
            const res = await fetch("/api/channels/preview", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ content, default_group, default_country })
            });

            if (res.ok) {
              const data = await res.json();
              detectedImportChannels = data.channels || [];
              const count = detectedImportChannels.length;

              if (count > 0) {
                previewBox.style.display = "block";
                const totalSources = detectedImportChannels.reduce((sum, c) => sum + (c.sources ? c.sources.length : 1), 0);
                previewBadge.innerText = "✨ Detected " + count + " Channels (" + totalSources + " Content IDs)";
                previewBadge.className = "chip-status-success";

                previewList.innerHTML = detectedImportChannels.slice(0, 50).map((c, i) => `
                  <div style="display: flex; align-items: center; justify-content: space-between; padding: 4px 8px; background: var(--surface-bg); border-radius: 4px;">
                    <div style="display: flex; align-items: center; gap: 6px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      <span style="color: var(--text-tertiary); font-family: var(--font-mono); font-size: 11px;">#${i + 1}</span>
                      <span style="font-weight: 600; color: #fff;">${c.name}</span>
                      ${c.country ? `<span class="chip-filter" style="font-size: 10px; padding: 0 4px;">${c.country}</span>` : ''}
                      <span style="font-size: 11px; color: var(--text-tertiary);">(${c.group})</span>
                    </div>
                    <span class="chip-status-success" style="font-size: 10px; padding: 0 6px;">🛡️ ${(c.sources || []).length} src</span>
                  </div>
                `).join("");

                if (count > 50) {
                  previewList.innerHTML += `<div style="text-align: center; color: var(--text-tertiary); font-size: 11px; padding: 4px;">...and ${count - 50} more channels</div>`;
                }

                btn.disabled = false;
                btnText.innerText = "Import " + count + " Channel" + (count > 1 ? "s" : "");
              } else {
                previewBox.style.display = "block";
                previewBadge.innerText = "⚠ No valid 40-character Content IDs found";
                previewBadge.className = "chip-status-warning";
                previewList.innerHTML = `<div style="color: var(--text-secondary); padding: 8px;">Please ensure your input contains at least one valid 40-character hexadecimal AceStream Content ID.</div>`;
                btn.disabled = true;
                btnText.innerText = "Import Channels";
              }
            }
          } catch (err) {
            console.error("Preview fetch error", err);
          }
        }

        async function executeChannelImport() {
          const content = document.getElementById("importTextContent").value.trim();
          const default_group = document.getElementById("importDefaultGroup").value.trim() || "General";
          const default_country = document.getElementById("importDefaultCountry").value.trim() || "";
          const mode = document.getElementById("importMode").value || "merge";
          const btn = document.getElementById("executeImportBtn");
          const btnText = document.getElementById("executeImportBtnText");

          btn.disabled = true;
          btnText.innerText = "Importing...";

          try {
            const res = await fetch("/api/channels/import", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ content, default_group, default_country, mode })
            });

            if (res.ok) {
              const data = await res.json();
              showToast("Successfully imported " + data.count + " channels!", true);
              closeImportModal();
              document.getElementById("importTextContent").value = "";
              document.getElementById("importPreviewBox").style.display = "none";
              // Reload channels
              const chRes = await fetch("/api/channels");
              if (chRes.ok) {
                allChannels = await chRes.json();
                renderCategoryTabs();
                updateFleetHealthMetrics();
                filterChannels();
              }
            } else {
              const err = await res.json();
              showToast("Import failed: " + (err.error || "Check input format"), false);
            }
          } catch (err) {
            showToast("Network error while importing channels", false);
          } finally {
            btn.disabled = false;
            btnText.innerText = "Import Channels";
          }
        }

        // Export Modal Controls
        async function openExportModal() {
          const modal = document.getElementById("exportModal");
          modal.classList.add("active");
          const textarea = document.getElementById("exportPreviewText");
          textarea.value = "Loading channel export...";

          try {
            const res = await fetch("/api/channels/export?format=txt");
            if (res.ok) {
              const text = await res.text();
              textarea.value = text;
            } else {
              textarea.value = "Failed to load channel export preview.";
            }
          } catch (_) {
            textarea.value = "Failed to connect to export API.";
          }
        }

        function closeExportModal() {
          document.getElementById("exportModal").classList.remove("active");
        }

        function copyExportText(btn = null) {
          const text = document.getElementById("exportPreviewText").value;
          if (!text || !text.trim()) {
            showToast("Export preview is empty!", false);
            return;
          }
          copyText(text, "All channels copied in Content ID format!", btn);
        }

        // In-Dashboard Web Video Player Modal (MPEG-TS Live Player)
        function openWebPlayerModal(title, streamUrl) {
          activeWebPlayerTitle = title;
          activeWebPlayerUrl = streamUrl;

          const titleEl = document.getElementById("webPlayerChannelName");
          if (titleEl) titleEl.innerText = title;
          const modal = document.getElementById("webPlayerModal");
          if (modal) modal.classList.add("active");

          const videoElem = document.getElementById("webVideoPlayer");
          const statsBadge = document.getElementById("playerStatsBadge");

          // Reset existing player instance cleanly
          if (mpegtsPlayerInstance) {
            try {
              mpegtsPlayerInstance.pause();
              mpegtsPlayerInstance.unload();
              mpegtsPlayerInstance.detachMediaElement();
              mpegtsPlayerInstance.destroy();
            } catch (_) {}
            mpegtsPlayerInstance = null;
          }

          if (videoElem) {
            videoElem.pause();
            videoElem.removeAttribute("src");
            videoElem.load();
          }

          if (window.mpegts && mpegts.isSupported()) {
            if (statsBadge) statsBadge.innerText = "MSE Connecting...";
            try {
              mpegtsPlayerInstance = mpegts.createPlayer({
                type: "mse",
                isLive: true,
                url: streamUrl
              }, {
                enableWorker: true,
                lazyLoad: false,
                stashInitialSize: 512 * 1024,
                liveBufferLatencyChasing: false,
                autoCleanupSourceBuffer: true,
                autoCleanupMaxBackwardDuration: 60,
                autoCleanupMinBackwardDuration: 30
              });

              mpegtsPlayerInstance.attachMediaElement(videoElem);
              mpegtsPlayerInstance.load();
              const p = mpegtsPlayerInstance.play();
              if (p && p.catch) {
                p.catch(err => {
                  console.log("Autoplay blocked or waiting user gesture:", err);
                });
              }

              mpegtsPlayerInstance.on(mpegts.Events.STATISTICS_INFO, (stat) => {
                if (stat && stat.speed && statsBadge) {
                  statsBadge.innerText = "MSE: " + Math.round(stat.speed) + " KB/s";
                }
              });

              mpegtsPlayerInstance.on(mpegts.Events.ERROR, (errType, errDetail) => {
                console.warn("MPEG-TS Error:", errType, errDetail);
                if (statsBadge) statsBadge.innerText = "MSE: " + errType;
              });
            } catch (err) {
              console.warn("mpegts.createPlayer error:", err);
              if (statsBadge) statsBadge.innerText = "Direct Stream";
              if (videoElem) {
                videoElem.src = streamUrl;
                videoElem.play().catch(() => {});
              }
            }
          } else {
            if (statsBadge) statsBadge.innerText = "Native Video Fallback";
            if (videoElem) {
              videoElem.src = streamUrl;
              videoElem.play().catch(() => {});
            }
          }
        }

        function closeWebPlayerModal() {
          const modal = document.getElementById("webPlayerModal");
          if (modal) modal.classList.remove("active");

          const videoElem = document.getElementById("webVideoPlayer");
          if (mpegtsPlayerInstance) {
            try {
              mpegtsPlayerInstance.pause();
              mpegtsPlayerInstance.unload();
              mpegtsPlayerInstance.detachMediaElement();
              mpegtsPlayerInstance.destroy();
            } catch (_) {}
            mpegtsPlayerInstance = null;
          }

          if (videoElem) {
            videoElem.pause();
            videoElem.removeAttribute("src");
            videoElem.load();
          }
        }

        function openExternalFromWebPlayer() {
          closeWebPlayerModal();
          openLauncherModal(activeWebPlayerTitle, activeWebPlayerUrl);
        }

        // Stream Launcher Modal
        function openLauncherModal(title, streamUrl) {
          document.getElementById("launcherModalTitle").innerText = title;
          document.getElementById("launcherStreamUrl").value = streamUrl;

          // External Video Player Protocols
          document.getElementById("launchVlc").href = "vlc://" + streamUrl;
          document.getElementById("launchIina").href = "iina://weblink?url=" + encodeURIComponent(streamUrl);
          document.getElementById("launchPot").href = "potplayer://" + streamUrl;
          document.getElementById("launchBrowser").href = streamUrl;

          document.getElementById("launcherModal").classList.add("active");
        }

        function closeLauncherModal() {
          document.getElementById("launcherModal").classList.remove("active");
        }

        function copyLauncherUrl(btn = null) {
          const url = document.getElementById("launcherStreamUrl").value;
          if (!url || !url.trim()) {
            showToast("Stream URL is empty!", false);
            return;
          }
          copyText(url, "Stream URL copied!", btn);
        }

        // QR Code Modal
        function openQrModal() {
          const currentM3u = document.getElementById("m3uUrlInput") ? document.getElementById("m3uUrlInput").value : (baseUrl + "/playlist.m3u8");
          const qrUrl = "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=" + encodeURIComponent(currentM3u);
          document.getElementById("qrImageElement").src = qrUrl;
          const qrDisplay = document.getElementById("qrM3uDisplay");
          if (qrDisplay) qrDisplay.innerText = currentM3u;
          document.getElementById("qrModal").classList.add("active");
        }

        function closeQrModal() {
          document.getElementById("qrModal").classList.remove("active");
        }

        // Xtream Codes Modal & Auth Settings
        function openXtreamModal() {
          document.getElementById("xtreamModal").classList.add("active");
        }

        function closeXtreamModal() {
          document.getElementById("xtreamModal").classList.remove("active");
        }

        function onAuthToggleChange() {
          const isChecked = document.getElementById("authToggleInput").checked;
          const badge = document.getElementById("authStatusBadge");
          if (isChecked) {
            badge.className = "badge-status badge-enabled";
            badge.textContent = "ENABLED";
            const userIn = document.getElementById("xtreamUserInput");
            const passIn = document.getElementById("xtreamPassInput");
            if (!userIn.value.trim()) userIn.value = "admin";
            if (!passIn.value.trim()) generateRandomPass();
          } else {
            badge.className = "badge-status badge-disabled";
            badge.textContent = "DISABLED (OPEN)";
          }
        }

        function generateRandomPass() {
          const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
          let res = "";
          const vals = new Uint8Array(10);
          window.crypto.getRandomValues(vals);
          for (let i = 0; i < 10; i++) {
            res += chars[vals[i] % chars.length];
          }
          document.getElementById("xtreamPassInput").value = res;
          showToast("Generated new random password!");
        }

        async function saveXtreamSettings() {
          const btn = document.getElementById("saveXtreamBtn");
          const originalContent = btn.innerHTML;
          const isAuthEnabled = document.getElementById("authToggleInput").checked;
          const userVal = document.getElementById("xtreamUserInput").value.trim();
          const passVal = document.getElementById("xtreamPassInput").value.trim();
          const epgVal = document.getElementById("xtreamEpgInput").value.trim();

          if (isAuthEnabled && (!userVal || !passVal)) {
            showToast("Username and Password are required when authentication is enabled!", false);
            return;
          }

          btn.disabled = true;
          btn.innerHTML = "<span>Saving...</span>";

          try {
            const resp = await fetch("/api/settings", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                auth_enabled: isAuthEnabled,
                auth_username: userVal,
                auth_password: passVal,
                epg_url: epgVal
              })
            });

            if (!resp.ok) {
              const errData = await resp.json().catch(() => ({}));
              throw new Error(errData.error || "Failed to update settings");
            }

            const data = await resp.json();
            const settings = data.settings || {
              auth_enabled: isAuthEnabled,
              auth_username: userVal,
              auth_password: passVal,
              epg_url: epgVal
            };

            appSettings = settings;
            updateAuthDependentLinks(settings);
            filterChannels();

            showToast("Xtream & Auth settings saved successfully!");
            btn.innerHTML = "<span>✓ Saved!</span>";
            setTimeout(() => {
              btn.innerHTML = originalContent;
              btn.disabled = false;
            }, 1800);
          } catch (err) {
            showToast(err.message || "Error saving settings", false);
            btn.innerHTML = originalContent;
            btn.disabled = false;
          }
        }

        function updateAuthDependentLinks(settings) {
          const isAuth = settings.auth_enabled;
          const user = settings.auth_username || "";
          const pass = settings.auth_password || "";

          let m3uUrl = baseUrl + "/playlist.m3u8";
          if (isAuth && user && pass) {
            m3uUrl += "?username=" + encodeURIComponent(user) + "&password=" + encodeURIComponent(pass);
          }

          const m3uInput = document.getElementById("m3uUrlInput");
          if (m3uInput) m3uInput.value = m3uUrl;

          const downloadLink = document.getElementById("m3uDownloadLink");
          if (downloadLink) downloadLink.href = m3uUrl;

          const qrDisplay = document.getElementById("qrM3uDisplay");
          if (qrDisplay) qrDisplay.innerText = m3uUrl;
        }

        function copyInput(elementId, successMsg, btn = null) {
          const input = document.getElementById(elementId);
          const val = input ? input.value.trim() : "";
          if (!val) {
            showToast("Field is empty — nothing to copy!", false);
            return;
          }
          copyText(val, successMsg || "Copied to clipboard!", btn);
        }

        function closeOnBackdrop(e, modalId) {
          if (e.target.id === modalId) {
            if (modalId === "webPlayerModal") {
              closeWebPlayerModal();
            } else {
              document.getElementById(modalId).classList.remove("active");
            }
          }
        }

        async function forceResetSession() {
          try {
            await fetch("/restart");
            showToast("Session reset to Idle successfully!");
            pollStats();
          } catch (_) {
            showToast("Failed to reset session", false);
          }
        }

        async function stopSingleChannel(channelKey, name) {
          try {
            await fetch("/restart?channel=" + encodeURIComponent(channelKey));
            showToast("Stream '" + (name || channelKey) + "' stopped successfully!");
            pollStats();
          } catch (_) {
            showToast("Failed to stop stream", false);
          }
        }

        function findChannelMeta(key, target, activeHash) {
          if (!allChannels || !Array.isArray(allChannels)) return null;
          let match = allChannels.find(ch => ch.id === key || ch.id === target);
          if (match) return match;
          const cleanTarget = (target || "").toLowerCase();
          const cleanHash = (activeHash || "").toLowerCase();
          match = allChannels.find(ch =>
            (ch.sources || []).some(s => {
              const ls = s.toLowerCase();
              return ls === cleanTarget || ls === cleanHash;
            })
          );
          return match || null;
        }

        function updateCatalogLiveBadges(channels) {
          const activeMap = new Map();
          (channels || []).forEach(c => {
            if (c.status === "streaming" || c.status === "starting") {
              if (c.channel_key) activeMap.set(c.channel_key, c);
              if (c.target) activeMap.set(c.target, c);
              if (c.active_channel) activeMap.set(c.active_channel, c);
            }
          });

          // Update grid cards
          document.querySelectorAll(".channel-card-sf").forEach(card => {
            const id = card.getAttribute("data-id");
            const channelObj = allChannels.find(ch => ch.id === id);
            let activeInfo = activeMap.get(id);

            if (!activeInfo && channelObj && channelObj.sources) {
              for (const s of channelObj.sources) {
                if (activeMap.has(s)) {
                  activeInfo = activeMap.get(s);
                  break;
                }
              }
            }

            let badge = card.querySelector(".poster-live-overlay-badge");
            if (activeInfo) {
              card.classList.add("is-broadcasting");
              let text = "";
              if (activeInfo.status === "starting") {
                const prog = activeInfo.progress;
                text = (prog && prog > 0) ? ("⏳ PREBUF " + prog + "%") : "⏳ CONNECTING...";
              } else {
                const viewers = activeInfo.client_count || 0;
                text = viewers > 0 ? ("● LIVE (" + viewers + ")") : "● LIVE";
              }
              if (!badge) {
                badge = document.createElement("div");
                badge.className = "poster-live-overlay-badge";
                const posterBox = card.querySelector(".poster-box");
                if (posterBox) posterBox.appendChild(badge);
              }
              badge.innerText = text;
              if (activeInfo.status === "starting") {
                badge.style.background = "rgba(234, 179, 8, 0.9)";
              } else {
                badge.style.background = "rgba(225, 29, 72, 0.95)";
              }
            } else {
              card.classList.remove("is-broadcasting");
              if (badge) badge.remove();
            }
          });

          // Update table rows
          document.querySelectorAll("#channelTableBody tr").forEach(row => {
            const id = row.getAttribute("data-id");
            const channelObj = allChannels.find(ch => ch.id === id);
            let activeInfo = activeMap.get(id);

            if (!activeInfo && channelObj && channelObj.sources) {
              for (const s of channelObj.sources) {
                if (activeMap.has(s)) {
                  activeInfo = activeMap.get(s);
                  break;
                }
              }
            }

            let liveIndicator = row.querySelector(".table-live-indicator");
            if (activeInfo) {
              row.classList.add("table-row-live");
              if (!liveIndicator) {
                const nameCell = row.children[1];
                if (nameCell) {
                  liveIndicator = document.createElement("span");
                  liveIndicator.className = "table-live-indicator chip-status-success";
                  liveIndicator.style.marginLeft = "6px";
                  liveIndicator.style.fontSize = "10px";
                  liveIndicator.innerText = "● LIVE";
                  nameCell.appendChild(liveIndicator);
                }
              }
            } else {
              row.classList.remove("table-row-live");
              if (liveIndicator) liveIndicator.remove();
            }
          });
        }

        function copyM3uUrl(btn = null) {
          const input = document.getElementById("m3uUrlInput");
          if (!input || !input.value.trim()) {
            showToast("M3U8 Playlist link is empty!", false);
            return;
          }
          const targetBtn = btn || document.getElementById("copyM3uBtn");
          copyText(input.value, "M3U8 Playlist link copied!", targetBtn);
        }

        function copyText(text, successMsg, btn = null) {
          if (!text && text !== 0) {
            showToast("Nothing to copy!", false);
            return;
          }

          function flashBtn() {
            if (!btn) return;
            const originalHtml = btn.innerHTML;
            if (btn.tagName === "BUTTON") {
              if (btn.classList.contains("btn-icon")) {
                btn.innerHTML = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--color-success)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>';
              } else {
                btn.innerHTML = "<span>✓ Copied!</span>";
              }
              setTimeout(() => { btn.innerHTML = originalHtml; }, 1800);
            }
          }

          function fallbackCopy() {
            try {
              const textarea = document.createElement("textarea");
              textarea.value = String(text);
              textarea.style.position = "fixed";
              textarea.style.top = "-9999px";
              textarea.style.left = "-9999px";
              textarea.style.opacity = "0";
              textarea.setAttribute("readonly", "");
              document.body.appendChild(textarea);
              textarea.select();
              textarea.setSelectionRange(0, textarea.value.length);
              const successful = document.execCommand("copy");
              document.body.removeChild(textarea);
              if (successful) {
                showToast(successMsg || "Copied to clipboard!");
                flashBtn();
              } else {
                showToast("Failed to copy to clipboard", false);
              }
            } catch (_) {
              showToast("Failed to copy to clipboard", false);
            }
          }

          if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(String(text)).then(() => {
              showToast(successMsg || "Copied to clipboard!");
              flashBtn();
            }).catch(() => {
              fallbackCopy();
            });
          } else {
            fallbackCopy();
          }
        }

        function showToast(msg, isSuccess = true) {
          const shelf = document.getElementById("toastShelf");
          const toast = document.createElement("div");
          toast.className = "toast-message";
          toast.style.borderLeft = isSuccess ? "4px solid var(--color-success)" : "4px solid var(--color-error)";
          toast.innerHTML = (isSuccess ? "✓ " : "✕ ") + msg;
          shelf.appendChild(toast);
          setTimeout(() => {
            toast.style.opacity = "0";
            toast.style.transform = "translateY(15px)";
            toast.style.transition = "all 0.25s";
            setTimeout(() => toast.remove(), 250);
          }, 3200);
        }

        // System 1-Click Updater Controller
        let currentSystemVersionInfo = null;
        let updateRebootInterval = null;

        async function checkSystemVersion(force = false) {
          const badgeText = document.getElementById("updateBadgeText");
          const badgeBtn = document.getElementById("updateBadgeBtn");
          if (force && badgeText) badgeText.innerText = "Checking...";

          try {
            const url = "/api/system/version" + (force ? "?force=true" : "");
            const res = await fetch(url);
            if (!res.ok) return;
            const data = await res.json();
            currentSystemVersionInfo = data;

            // Update Header Badge
            if (badgeBtn && badgeText) {
              if (data.has_update) {
                badgeBtn.classList.add("has-update");
                badgeText.innerHTML = "🚀 Bản mới: v" + data.latest_version;
              } else {
                badgeBtn.classList.remove("has-update");
                badgeText.innerHTML = "v" + data.current_version + " ✓";
              }
            }

            // Update Modal elements if present
            const modalCurrent = document.getElementById("modalCurrentVer");
            const modalLatest = document.getElementById("modalLatestVer");
            const modalBadge = document.getElementById("modalUpdateBadgeStatus");
            const modalNotes = document.getElementById("modalReleaseNotes");
            const modalLink = document.getElementById("modalReleaseLink");
            const btnExec = document.getElementById("btnExecuteUpdate");

            if (modalCurrent) modalCurrent.innerText = "v" + data.current_version;
            if (modalLatest) modalLatest.innerText = "v" + data.latest_version;
            if (modalNotes) modalNotes.innerText = data.release_notes || "Không có ghi chú phát hành.";
            if (modalLink && data.release_url) modalLink.href = data.release_url;

            if (modalBadge) {
              if (data.has_update) {
                modalBadge.innerText = "Có bản mới 🚀";
                modalBadge.style.background = "rgba(225, 29, 72, 0.2)";
                modalBadge.style.color = "#FF5A79";
              } else {
                modalBadge.innerText = "Đã mới nhất ✓";
                modalBadge.style.background = "rgba(16, 185, 129, 0.15)";
                modalBadge.style.color = "#10B981";
              }
            }

            if (btnExec) {
              if (data.has_update) {
                btnExec.innerHTML = "⚡ Cập nhật lên v" + data.latest_version + " (1-Click)";
              } else {
                btnExec.innerHTML = "⚡ Cập nhật lại (Re-pull image)";
              }
            }
          } catch (err) {
            console.warn("Failed to check system version:", err);
          }
        }

        function openUpdateModal() {
          const modal = document.getElementById("updateModal");
          if (modal) {
            modal.classList.add("active");
            checkSystemVersion();
          }
        }

        function closeUpdateModal() {
          const modal = document.getElementById("updateModal");
          if (modal) modal.classList.remove("active");
        }

        async function executeSystemUpdate() {
          const targetVer = (currentSystemVersionInfo && currentSystemVersionInfo.latest_version) ? currentSystemVersionInfo.latest_version : "";
          const confirmMsg = targetVer
            ? "Bắt đầu cập nhật hệ thống lên phiên bản v" + targetVer + "? Containers sẽ tự tải Image mới và khởi động lại."
            : "Bắt đầu cập nhật hệ thống? Containers sẽ tự tải Image mới và khởi động lại.";

          if (!confirm(confirmMsg)) return;

          const btnExec = document.getElementById("btnExecuteUpdate");
          const progressBox = document.getElementById("updateProgressBox");
          const progressText = document.getElementById("updateProgressText");
          const countdown = document.getElementById("updateCountdownTimer");

          if (btnExec) {
            btnExec.disabled = true;
            btnExec.innerText = "Đang kích hoạt cập nhật...";
          }

          if (progressBox) progressBox.style.display = "block";
          if (progressText) progressText.innerText = "Đang gửi lệnh cập nhật đến máy chủ...";

          try {
            const resp = await fetch("/api/system/update", { method: "POST" });
            const data = await resp.json();

            if (resp.ok && (data.status === "updating" || data.status === "ok")) {
              if (progressText) progressText.innerText = data.message || "Đã gửi lệnh cập nhật! Đang chờ khởi động lại...";
              pollServerReboot(targetVer);
            } else if (data.status === "manual_required" || data.command) {
              if (progressBox) progressBox.style.display = "none";
              if (btnExec) {
                btnExec.disabled = false;
                btnExec.innerText = "Cập nhật thủ công";
              }
              showToast("Hệ thống yêu cầu chạy lệnh thủ công qua terminal.", false);
            } else {
              throw new Error(data.message || data.error || "Update trigger failed");
            }
          } catch (err) {
            if (progressBox) progressBox.style.display = "none";
            if (btnExec) {
              btnExec.disabled = false;
              btnExec.innerText = "⚡ Thử lại";
            }
            showToast("Lỗi khi kích hoạt cập nhật: " + err.message, false);
          }
        }

        function pollServerReboot(targetVer) {
          let secondsLeft = 25;
          let serverWentOffline = false;
          const countdown = document.getElementById("updateCountdownTimer");
          const progressText = document.getElementById("updateProgressText");

          if (updateRebootInterval) clearInterval(updateRebootInterval);

          updateRebootInterval = setInterval(async () => {
            secondsLeft--;
            if (countdown) {
              countdown.innerText = "Đang kiểm tra kết nối lại sau: " + Math.max(0, secondsLeft) + "s";
            }

            try {
              const check = await fetch("/health?t=" + Date.now(), { cache: "no-store" });
              if (check.ok && (serverWentOffline || secondsLeft <= 19)) {
                clearInterval(updateRebootInterval);
                updateRebootInterval = null;
                if (progressText) progressText.innerText = "✓ Cập nhật hoàn tất! Đang tải lại trang...";
                showToast("Hệ thống đã nâng cấp thành công!", true);
                setTimeout(() => {
                  window.location.reload();
                }, 1200);
              }
            } catch (_) {
              serverWentOffline = true;
              if (progressText) progressText.innerText = "Dịch vụ đang khởi động lại container mới...";
            }

            if (secondsLeft <= -40) {
              clearInterval(updateRebootInterval);
              updateRebootInterval = null;
              if (progressText) {
                progressText.innerHTML = "Quá trình cập nhật mất nhiều thời gian hơn dự kiến. <br><button class='btn btn-primary btn-sm' onclick='window.location.reload()' style='margin-top:8px;'>Tải lại trang ngay</button>";
              }
            }
          }, 2000);
        }

        // Realtime Polling
        async function pollStats() {
          try {
            const res = await fetch("/stat");
            if (!res.ok) return;
            const data = await res.json();

            // Status Pill Elements
            const pill = document.getElementById("statusPill");
            const dot = document.getElementById("statusDot");
            const text = document.getElementById("statusText");

            const channels = (data.channels || []).filter(c => c && c.status);

            if (channels.length > 0) {
              const streamingCount = channels.filter(c => c.status === "streaming").length;
              const startingCount = channels.filter(c => c.status === "starting").length;

              if (streamingCount > 0) {
                pill.className = "status-pill status-live";
                dot.className = "pulse-dot pulse-active";
              } else if (startingCount > 0) {
                pill.className = "status-pill status-starting";
                dot.className = "pulse-dot pulse-active";
              } else {
                pill.className = "status-pill status-starting";
                dot.className = "pulse-dot";
              }

              if (channels.length === 1) {
                const c = channels[0];
                const meta = findChannelMeta(c.channel_key, c.target, c.active_channel);
                const title = c.channel_name || meta?.name || c.channel_key;
                if (c.status === "streaming") {
                  text.innerText = "LIVE: " + title;
                } else if (c.progress && c.progress > 0) {
                  text.innerText = "PREBUF " + c.progress + "%: " + title;
                } else {
                  text.innerText = "CONNECTING: " + title;
                }
              } else {
                text.innerText = "LIVE: " + channels.length + " ACTIVE STREAMS";
              }
            } else {
              pill.className = "status-pill status-idle";
              dot.className = "pulse-dot";
              text.innerText = "SYSTEM READY";
            }

            // Extract active channel keys and update fleet health metrics
            const activeKeys = new Set();
            channels.forEach(c => {
              if (c.channel_key) activeKeys.add(c.channel_key);
              if (c.target) activeKeys.add(c.target);
              if (c.active_channel) activeKeys.add(c.active_channel);
            });
            updateFleetHealthMetrics(activeKeys);

            // Update live indicators on catalog cards and table rows
            updateCatalogLiveBadges(channels);
          } catch (_) {}
        }

        // Global hotkey: '/' focuses search box, 'Escape' closes modals
        window.addEventListener("keydown", (e) => {
          if (e.key === "/" && document.activeElement.tagName !== "INPUT" && document.activeElement.tagName !== "TEXTAREA") {
            e.preventDefault();
            document.getElementById("channelSearch").focus();
          } else if (e.key === "Escape") {
            closeWebPlayerModal();
            closeChannelModal();
            closeLauncherModal();
            closeQrModal();
            closeExportModal();
            closeImportModal();
            closeXtreamModal();
            closeUpdateModal();
          }
        });

        // Initialize
        renderCategoryTabs();
        updateFleetHealthMetrics();
        renderChannels(allChannels);
        setInterval(pollStats, 2000);
        pollStats();
        checkSystemVersion();
      </script>
    </body>
    </html>
    """
  end
end
