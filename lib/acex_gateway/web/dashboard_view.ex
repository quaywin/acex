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
  def render(base_url, channels, groups \\ nil) do
    groups_list = groups || AcexGateway.Channels.Store.list_groups()
    channels_json = Jason.encode!(channels)
    groups_json = Jason.encode!(groups_list)
    auth_enabled = AcexGateway.Config.auth_enabled?()
    auth_user = AcexGateway.Config.auth_username()
    auth_pass = AcexGateway.Config.auth_password()
    epg_url = AcexGateway.Config.epg_url()
    parsed_uri = URI.parse(base_url)
    server_port = to_string(parsed_uri.port || 8686)

    m3u_hls_url =
      if auth_enabled and auth_user != "" and auth_pass != "" do
        "#{base_url}/hls/#{URI.encode_www_form(auth_user)}/#{URI.encode_www_form(auth_pass)}.m3u8"
      else
        "#{base_url}/hls.m3u8"
      end

    m3u_ts_url =
      if auth_enabled and auth_user != "" and auth_pass != "" do
        "#{base_url}/ts/#{URI.encode_www_form(auth_user)}/#{URI.encode_www_form(auth_pass)}.m3u8"
      else
        "#{base_url}/ts.m3u8"
      end

    m3u_display_url = m3u_hls_url

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
      <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js"></script>
      <script>
        window['__onGCastApiAvailable'] = function(isAvailable) {
          if (isAvailable) {
            window.isCastApiAvailable = true;
            if (typeof initGoogleCastFramework === "function") {
              initGoogleCastFramework();
            }
          }
        };
      </script>
      <script src="https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1"></script>
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
           Channel Card: Compact & Streamlined Modern Poster
           ------------------------------------------------------------- */
        .channel-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
          gap: 12px;
        }

        .channel-card-sf {
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-sm);
          overflow: hidden;
          box-shadow: var(--shadow-sm);
          display: flex;
          flex-direction: column;
          position: relative;
          transition: transform 0.2s cubic-bezier(0.2, 0, 0, 1), box-shadow 0.2s ease, border-color 0.2s ease;
        }

        .channel-card-sf:hover {
          transform: translateY(-2px);
          box-shadow: var(--shadow-hover);
          border-color: rgba(225, 29, 72, 0.45);
          z-index: 2;
        }

        .poster-box {
          position: relative;
          width: 100%;
          aspect-ratio: 2.2 / 1;
          max-height: 96px;
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
          transform: scale(1.05);
        }

        .poster-fallback {
          width: 100%;
          height: 100%;
          background: radial-gradient(circle at 50% 30%, #262626 0%, #111111 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: var(--font-headline);
          font-size: 24px;
          font-weight: 700;
          color: rgba(255, 255, 255, 0.25);
          letter-spacing: 0.05em;
        }

        .poster-scrim {
          position: absolute;
          inset: 0;
          background: linear-gradient(180deg, rgba(15,15,15,0.15) 0%, rgba(20,20,20,0.9) 100%);
          pointer-events: none;
        }

        .poster-badges-top {
          position: absolute;
          top: 6px;
          left: 6px;
          right: 6px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 4px;
          pointer-events: none;
          z-index: 1;
        }

        .poster-badges-top span {
          font-size: 10px !important;
          padding: 2px 6px !important;
          line-height: 1.2 !important;
          border-radius: var(--radius-sm);
          backdrop-filter: blur(4px);
          white-space: nowrap;
        }

        /* Center Red Play Button on Poster Hover */
        .poster-play-btn {
          position: absolute;
          width: 36px;
          height: 36px;
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
          transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
          z-index: 2;
        }

        .poster-play-btn svg {
          width: 16px;
          height: 16px;
          margin-left: 2px;
        }

        .channel-card-sf:hover .poster-play-btn {
          opacity: 1;
          transform: scale(1);
        }

        .poster-play-btn:hover {
          background: var(--color-primary-hover);
          transform: scale(1.08) !important;
        }

        /* Card Content Area - Compact & Space-Efficient */
        .card-content {
          padding: 8px 10px 10px;
          display: flex;
          flex-direction: column;
          flex: 1;
          gap: 4px;
        }

        .card-head {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 6px;
        }

        .card-title {
          font-family: var(--font-headline);
          font-size: 14px;
          font-weight: 600;
          letter-spacing: 0.01em;
          color: #FFFFFF;
          line-height: 1.2;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
        }

        .card-type-tag {
          font-family: var(--font-mono);
          font-size: 10px;
          color: var(--text-tertiary);
          background: var(--border-default);
          padding: 1px 5px;
          border-radius: var(--radius-sm);
          text-transform: uppercase;
        }

        .card-slug {
          font-family: var(--font-mono);
          font-size: 11px;
          color: var(--text-tertiary);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          opacity: 0.75;
        }

        /* Sources Accordion - Compact */
        .sources-accordion {
          border-top: 1px solid var(--border-subtle);
          padding-top: 4px;
          margin-top: 2px;
        }

        .sources-toggle {
          display: flex;
          justify-content: space-between;
          align-items: center;
          font-size: 11px;
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          user-select: none;
          padding: 2px 0;
          transition: color 0.2s;
        }

        .sources-toggle:hover {
          color: #FFFFFF;
        }

        .sources-list {
          display: none;
          flex-direction: column;
          gap: 3px;
          margin-top: 4px;
          max-height: 120px;
          overflow-y: auto;
        }

        .sources-list.show {
          display: flex;
        }

        .source-item {
          display: flex;
          align-items: center;
          gap: 5px;
          padding: 3px 6px;
          background: #111111;
          border-radius: var(--radius-sm);
          font-family: var(--font-mono);
          font-size: 11px;
          color: var(--text-secondary);
        }

        /* Channel Card Actions (Optimized 2-Row Layout, Never Overflows) */
        .card-action-bar {
          display: flex;
          flex-direction: column;
          gap: 5px;
          margin-top: 4px;
          padding-top: 6px;
          border-top: 1px solid var(--border-subtle);
        }

        .card-play-btns {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 6px;
          width: 100%;
        }

        .card-play-btns .btn {
          height: 26px;
          min-height: 26px;
          padding: 2px 6px;
          font-size: 11px;
          font-weight: 600;
          justify-content: center;
          gap: 4px;
          white-space: nowrap;
          border-radius: var(--radius-xs);
        }

        .card-tools-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: 4px;
          width: 100%;
        }

        .card-tool-btn {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          background: transparent;
          border: 1px solid transparent;
          color: var(--text-tertiary);
          font-size: 11px;
          font-family: inherit;
          padding: 2px 5px;
          border-radius: var(--radius-xs);
          cursor: pointer;
          transition: all 0.15s ease;
          white-space: nowrap;
        }
        .card-tool-btn:hover {
          color: #FFFFFF;
          background: rgba(255, 255, 255, 0.05);
          border-color: var(--border-subtle);
        }

        .card-tool-icons {
          display: inline-flex;
          align-items: center;
          gap: 3px;
        }

        .card-icon-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 24px;
          height: 24px;
          border-radius: var(--radius-xs);
          background: transparent;
          border: none;
          color: var(--text-tertiary);
          cursor: pointer;
          transition: all 0.15s ease;
          padding: 0;
        }
        .card-icon-btn:hover {
          color: #FFFFFF;
          background: rgba(255, 255, 255, 0.08);
        }
        .card-icon-btn-danger:hover {
          color: var(--color-danger);
          background: rgba(239, 68, 68, 0.15);
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

        .table-actions-group {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          justify-content: flex-end;
        }

        .table-actions-group .btn-xs {
          height: 26px;
          min-height: 26px;
          padding: 2px 8px;
          font-size: 11px;
          font-weight: 600;
          gap: 4px;
          white-space: nowrap;
        }

        .table-actions-group .btn-icon.btn-xs {
          width: 26px;
          height: 26px;
          min-width: 26px;
          padding: 0;
          display: inline-flex;
          align-items: center;
          justify-content: center;
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
            grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
            gap: 10px;
          }
          .card-content {
            padding: 8px 10px;
            gap: 4px;
          }
          .card-title {
            font-size: 13px;
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
          .fleet-health-banner {
            flex-direction: column;
            align-items: stretch;
            padding: 12px 14px;
            gap: 12px;
          }
          .fleet-metrics-group {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px 12px;
            width: 100%;
          }
          .fleet-metric-item {
            gap: 6px;
          }
          .fleet-metric-icon {
            width: 28px;
            height: 28px;
            font-size: 13px;
          }
          .fleet-metric-val {
            font-size: 16px;
          }
          .fleet-filter-bar {
            padding-bottom: 6px;
            -webkit-overflow-scrolling: touch;
          }
          .filter-tab-pill {
            padding: 5px 11px;
            font-size: 12px;
          }
          .input-row {
            flex-direction: column;
            align-items: stretch;
            gap: 6px;
          }
          .input-row .btn {
            width: 100%;
            justify-content: center;
          }
          .panel-actions-row {
            flex-wrap: wrap;
            gap: 6px;
          }
          .panel-actions-row .btn {
            flex: 1 1 calc(50% - 6px);
            min-width: 0;
            padding: 6px 8px;
            font-size: 12px;
          }
          .card-play-btns {
            gap: 4px;
          }
          .card-play-btns .btn {
            height: 24px;
            min-height: 24px;
            font-size: 10px;
            padding: 2px 4px;
          }
          .card-tool-btn {
            font-size: 10px;
            padding: 1px 3px;
          }
          .card-icon-btn {
            width: 22px;
            height: 22px;
          }
          .source-card-item {
            flex-direction: column;
            align-items: stretch;
            gap: 6px;
            padding: 8px 10px;
          }
          .source-card-actions {
            justify-content: flex-end;
          }
          .format-choice-grid {
            grid-template-columns: 1fr !important;
            gap: 8px !important;
          }
          .version-compare-banner {
            flex-direction: column !important;
            align-items: stretch !important;
            text-align: center;
            gap: 10px !important;
          }
          .version-compare-banner .version-arrow {
            transform: rotate(90deg);
            margin: 2px 0;
          }
          .update-modal-footer {
            flex-direction: column !important;
            align-items: stretch !important;
            gap: 8px !important;
          }
          .update-modal-footer .btn {
            width: 100% !important;
            justify-content: center !important;
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

        /* Selection Checkbox for Bulk Actions */
        .card-select-wrap {
          position: absolute;
          top: 8px;
          left: 8px;
          z-index: 4;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .channel-checkbox {
          width: 18px;
          height: 18px;
          cursor: pointer;
          accent-color: var(--color-primary);
          border-radius: 4px;
          opacity: 0.6;
          transition: opacity 0.2s, transform 0.2s;
        }

        .channel-card-sf:hover .channel-checkbox,
        .channel-checkbox:checked {
          opacity: 1;
          transform: scale(1.08);
        }

        .channel-card-sf.selected {
          border-color: var(--color-primary) !important;
          box-shadow: 0 0 0 2px rgba(225, 29, 72, 0.45), var(--shadow-md);
        }

        .channel-table tr.selected td {
          background: rgba(225, 29, 72, 0.08);
        }

        /* Floating Bulk Action Bar */
        .floating-bulk-bar {
          position: fixed;
          bottom: 24px;
          left: 50%;
          transform: translateX(-50%) translateY(120px);
          z-index: 999;
          background: rgba(18, 18, 18, 0.94);
          backdrop-filter: blur(16px);
          -webkit-backdrop-filter: blur(16px);
          border: 1px solid var(--border-hover);
          border-radius: var(--radius-full);
          padding: 8px 18px;
          display: flex;
          align-items: center;
          gap: 12px;
          box-shadow: 0 12px 32px rgba(0, 0, 0, 0.65), 0 0 0 1px rgba(255, 255, 255, 0.1);
          transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s ease;
          opacity: 0;
          pointer-events: none;
          max-width: 90vw;
        }

        .floating-bulk-bar.show {
          transform: translateX(-50%) translateY(0);
          opacity: 1;
          pointer-events: auto;
        }

        .bulk-count-badge {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          background: var(--color-primary);
          color: #FFFFFF;
          font-family: var(--font-headline);
          font-size: 13px;
          font-weight: 700;
          padding: 4px 10px;
          border-radius: var(--radius-full);
          letter-spacing: 0.03em;
          white-space: nowrap;
        }

        .bulk-select-group {
          background: var(--surface-input);
          color: var(--text-primary);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          padding: 5px 10px;
          font-size: 13px;
          outline: none;
          cursor: pointer;
        }
        .bulk-select-group:focus {
          border-color: var(--color-primary);
        }

        /* Group Modal Items */
        .group-manager-list {
          display: flex;
          flex-direction: column;
          gap: 6px;
          max-height: 280px;
          overflow-y: auto;
          margin-bottom: var(--space-md);
        }

        .group-manager-item {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 8px 12px;
          background: var(--surface-card);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          transition: border-color 0.2s;
        }

        .group-manager-item:hover {
          border-color: var(--border-hover);
        }

        .group-item-name {
          font-weight: 600;
          color: #FFFFFF;
          font-size: 14px;
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .group-channel-count {
          font-family: var(--font-mono);
          font-size: 11px;
          padding: 2px 7px;
          border-radius: var(--radius-sm);
          background: var(--surface-sunken);
          color: var(--text-secondary);
          border: 1px solid var(--border-subtle);
        }

        .chip-filter-interactive {
          cursor: pointer;
          transition: all 0.2s;
        }
        .chip-filter-interactive:hover {
          border-color: var(--color-primary);
          color: #FFFFFF;
          transform: scale(1.05);
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
            <button id="updateBadgeBtn" class="update-badge-btn" onclick="openUpdateModal()" title="Check & Update System">
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

            <div style="display: flex; gap: 8px; align-items: center; margin-top: 2px;">
              <span style="font-size: 11px; font-weight: 700; color: var(--text-tertiary); text-transform: uppercase; letter-spacing: 0.05em;">Format:</span>
              <button id="formatHlsBtn" type="button" class="btn btn-sm btn-primary" onclick="switchPlaylistFormat('hls')" style="border-radius: var(--radius-pill); padding: 4px 12px; font-size: 12px;">
                ⚡ HLS (CDN Cached)
              </button>
              <button id="formatTsBtn" type="button" class="btn btn-sm btn-secondary" onclick="switchPlaylistFormat('ts')" style="border-radius: var(--radius-pill); padding: 4px 12px; font-size: 12px;">
                🚀 Direct TS (Low Latency)
              </button>
            </div>

            <div class="input-row">
              <input type="text" id="m3uUrlInput" class="text-input-styled" readonly value="#{m3u_display_url}" data-hls="#{m3u_hls_url}" data-ts="#{m3u_ts_url}">
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
                <div class="fleet-metric-label">Total Channels</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-success);">🛡️</div>
              <div>
                <div class="fleet-metric-val" id="metricMultiChannels">0</div>
                <div class="fleet-metric-label">Redundant Sources</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-warning);">⚠️</div>
              <div>
                <div class="fleet-metric-val" id="metricSingleChannels">0</div>
                <div class="fleet-metric-label">Single Source</div>
              </div>
            </div>
            <div class="fleet-metric-item">
              <div class="fleet-metric-icon" style="color: var(--color-primary);">🔴</div>
              <div>
                <div class="fleet-metric-val" id="metricLiveChannels">0</div>
                <div class="fleet-metric-label">Active Streaming</div>
              </div>
            </div>
          </div>

          <div style="display: flex; align-items: center; gap: 8px;">
            <button class="btn btn-secondary btn-sm" onclick="pruneAllDeadSources(this)" title="Scan and automatically prune dead Content IDs across multi-source channels" style="color: var(--color-danger); border-color: rgba(239, 68, 68, 0.4);">
              <span>🧹 Prune All Dead Sources</span>
            </button>
          </div>
        </section>

        <!-- Channel Lineup Catalog -->
        <section class="lineup-section">
          <!-- Fleet Filter Chips -->
          <div class="fleet-filter-bar">
            <button class="filter-tab-pill active" id="filterPillAll" onclick="setFleetFilter('all')">All (<span id="countPillAll">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillLive" onclick="setFleetFilter('live')">🔴 Active (<span id="countPillLive">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillMulti" onclick="setFleetFilter('multi')">🛡️ Redundant (<span id="countPillMulti">0</span>)</button>
            <button class="filter-tab-pill" id="filterPillSingle" onclick="setFleetFilter('single')">⚠️ Single Source (<span id="countPillSingle">0</span>)</button>
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
                  <th style="width: 36px; text-align: center;"><input type="checkbox" id="selectAllCheckbox" class="channel-checkbox" onchange="toggleSelectAll(this)" title="Select all channels"></th>
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
            <a href="javascript:void(0)" onclick="openUpdateModal()" style="color: var(--text-secondary); text-decoration: none;" title="Check & Update System">v#{AcexGateway.version()}</a>
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
                <span id="autoDetectBadge" style="font-size: 11px; color: var(--color-success); font-weight: 600; display: none;">⚡ Auto-detected</span>
              </div>
              <input type="text" id="inputName" class="form-control" placeholder="e.g., K+ Sport 1 HD, Sky Sports Premier League" required oninput="handleChannelNameInput(this.value)">
            </div>
            <div class="modal-grid-2col" style="display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md);">
              <div class="form-group">
                <label class="form-label">Category / Group:</label>
                <input type="text" id="inputGroup" class="form-control" placeholder="Sports, News, Movies..." list="groupSuggestions">
              </div>
              <div class="form-group">
                <label class="form-label">Country (e.g. VN, UK, US):</label>
                <input type="text" id="inputCountry" class="form-control" placeholder="VN, UK, US, ES...">
              </div>
            </div>

            <!-- Enhanced Interactive Sources Manager -->
            <div class="form-group">
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                <label class="form-label" style="margin-bottom: 0;">AceStream Content IDs (Priority Order #1 &rarr; #N):</label>
                <div style="display: flex; gap: 6px;">
                  <button type="button" class="btn btn-secondary btn-xs" onclick="pasteModalSourcesFromClipboard()" style="padding: 2px 8px; font-size: 11px;">
                    📋 Paste from Clipboard
                  </button>
                  <button type="button" class="btn btn-secondary btn-xs" id="btnTestModalSources" onclick="testModalSources()" style="padding: 2px 8px; font-size: 11px;">
                    🔍 Test Sources
                  </button>
                </div>
              </div>

              <!-- Interactive Reorderable Sources List -->
              <div id="modalSourcesListContainer" style="margin-bottom: 6px; display: none; max-height: 160px; overflow-y: auto;">
                <!-- Populated dynamically via renderModalSourcesList() -->
              </div>

              <textarea id="inputSources" class="form-control" rows="3" placeholder="Enter or paste Content IDs (40-char hex), comma or newline separated" required oninput="handleSourcesTextareaInput(this.value)"></textarea>
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
              <input type="text" id="importDefaultGroup" class="form-control" style="padding: 6px 10px; font-size: 13px;" placeholder="Sports, Live TV..." value="Sports" list="groupSuggestions" oninput="debouncedImportPreview()">
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

          <div style="margin-bottom: var(--space-md); display: flex; flex-direction: column; gap: 10px;">
            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                <label class="form-label" style="margin-bottom: 0;">Direct MPEG-TS Stream URL (.ts):</label>
                <span style="font-size: 11px; color: var(--text-tertiary);">VLC, PotPlayer, TiviMate</span>
              </div>
              <div class="input-row">
                <input type="text" id="launcherStreamUrl" class="text-input-styled" readonly>
                <button class="btn btn-primary btn-sm" onclick="copyLauncherUrl(this)">Copy</button>
              </div>
            </div>

            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                <label class="form-label" style="margin-bottom: 0;">Chromecast / Universal HLS URL (.m3u8):</label>
                <span style="font-size: 11px; color: var(--text-tertiary);">Chromecast, Safari, Web Video Caster</span>
              </div>
              <div class="input-row">
                <input type="text" id="launcherCastUrl" class="text-input-styled" readonly style="font-family: var(--font-mono); font-size: 12px;">
                <button class="btn btn-secondary btn-sm" onclick="copyLauncherCastUrl(this)">Copy</button>
              </div>
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

      <!-- In-Dashboard Web Video Player Modal (HLS Live Player) -->
      <div id="webPlayerModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'webPlayerModal')">
        <div class="modal-window" style="max-width: 820px; padding: var(--space-md);">
          <div class="modal-top" style="margin-bottom: var(--space-sm);">
            <div>
              <h3 id="webPlayerTitle" style="display: flex; align-items: center; gap: 8px;">
                <span style="color: var(--color-primary);">▶</span>
                <span id="webPlayerChannelName">Live Stream Player</span>
              </h3>
              <p style="font-size: 12px; color: var(--text-secondary); margin-top: 2px;">
                Direct HLS live stream playback in browser
              </p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeWebPlayerModal()">✕</button>
          </div>

          <div class="video-player-box">
            <div class="video-player-hud">
              <span id="playerLiveBadge" class="chip-status-success" style="font-size: 11px;">● LIVE</span>
              <span id="playerStatsBadge" style="font-family: var(--font-mono); font-size: 11px; background: rgba(0,0,0,0.6); padding: 2px 8px; border-radius: 4px; color: var(--text-secondary);">HLS Engine</span>
              <span id="playerCastBadge" style="display: none; font-family: var(--font-mono); font-size: 11px; background: rgba(59, 130, 246, 0.3); border: 1px solid rgba(59, 130, 246, 0.6); padding: 2px 8px; border-radius: 4px; color: #93c5fd;">📺 Casting to TV</span>
            </div>
            <video id="webVideoPlayer" controls autoplay muted playsinline></video>
          </div>

          <div style="display: flex; justify-content: space-between; align-items: center; margin-top: var(--space-sm); flex-wrap: wrap; gap: 8px;">
            <div style="font-size: 12px; color: var(--text-tertiary);">
              💡 <em>Note:</em> Unmute on the video toolbar to enable audio. If your browser does not support the audio codec, use the external Desktop App button.
            </div>
            <div style="display: flex; gap: 6px; align-items: center;">
              <button id="castLauncherBtn" class="btn btn-secondary btn-sm" onclick="triggerCast()" title="Stream to Chromecast / Google TV" style="display: inline-flex; align-items: center; gap: 6px; position: relative;">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M2 16.1A5 5 0 0 1 5.9 20M2 12.05A9 9 0 0 1 9.95 20M2 8V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6"/>
                  <line x1="2" y1="20" x2="2.01" y2="20"/>
                </svg>
                <span id="castBtnText">Cast to TV</span>
                <google-cast-launcher id="googleCastLauncher" style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0.001; cursor: pointer;"></google-cast-launcher>
              </button>
              <button class="btn btn-secondary btn-sm" onclick="copyWebPlayerCastUrl(this)" title="Copy Chromecast / Universal HLS (.m3u8) URL">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                <span>Copy Cast URL</span>
              </button>
              <button class="btn btn-secondary btn-sm" onclick="openExternalFromWebPlayer()">
                <span>Open in Desktop App</span>
              </button>
              <button class="btn btn-primary btn-sm" onclick="closeWebPlayerModal()">
                <span>Close Player</span>
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
          <div class="format-choice-grid" style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: var(--space-sm); margin-bottom: var(--space-md);">
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
                <h3 style="font-size: 20px; font-weight: 700; color: #fff;">System Update</h3>
                <p style="font-size: 13px; color: var(--text-secondary); margin-top: 2px;">Check and upgrade to the latest release</p>
              </div>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeUpdateModal()">✕</button>
          </div>

          <div style="display: flex; flex-direction: column; gap: 14px; margin-top: 14px;">
            <!-- Version Comparison Banner -->
            <div class="version-compare-banner" style="background: rgba(255, 255, 255, 0.03); border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 14px; display: flex; align-items: center; justify-content: space-between;">
              <div>
                <div style="font-size: 11px; text-transform: uppercase; color: var(--text-tertiary); letter-spacing: 0.05em;">Current Version</div>
                <div style="font-family: var(--font-mono); font-size: 16px; font-weight: 700; color: #FFFFFF; margin-top: 2px;" id="modalCurrentVer">v#{AcexGateway.version()}</div>
              </div>
              <div class="version-arrow" style="font-size: 20px; color: var(--text-tertiary);">➔</div>
              <div>
                <div style="font-size: 11px; text-transform: uppercase; color: var(--text-tertiary); letter-spacing: 0.05em;">Latest Release</div>
                <div style="font-family: var(--font-mono); font-size: 16px; font-weight: 700; color: var(--color-primary);" id="modalLatestVer">Checking...</div>
              </div>
              <div id="modalUpdateBadgeStatus" style="padding: 4px 10px; border-radius: var(--radius-full); font-size: 12px; font-weight: 600; background: var(--border-default); color: var(--text-secondary);">
                Checking...
              </div>
            </div>

            <!-- Release Notes View -->
            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                <label class="form-label" style="font-size: 12px; margin-bottom: 0;">Release Notes (Changelog):</label>
                <a id="modalReleaseLink" href="https://github.com/quaywin/acex/releases" target="_blank" rel="noopener noreferrer" style="font-size: 12px; color: var(--color-primary); text-decoration: none;">View on GitHub ↗</a>
              </div>
              <div id="modalReleaseNotes" style="background: #0A0A0A; border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 12px; font-size: 13px; line-height: 1.5; color: var(--text-secondary); max-height: 180px; overflow-y: auto; white-space: pre-wrap; font-family: var(--font-mono);">Checking latest release from GitHub...</div>
            </div>

            <!-- Update In-Progress Box (Hidden by default) -->
            <div id="updateProgressBox" style="display: none; background: rgba(225, 29, 72, 0.08); border: 1px solid var(--color-primary); border-radius: var(--radius-sm); padding: 14px; text-align: center;">
              <div style="font-size: 24px; margin-bottom: 6px;">🔄</div>
              <div style="font-weight: 700; color: #FFFFFF; font-size: 15px;" id="updateProgressText">Upgrading system...</div>
              <div style="font-size: 12px; color: var(--text-secondary); margin-top: 4px;">Pulling new container image and restarting services. Page will reload automatically.</div>
              <div style="margin-top: 10px; font-family: var(--font-mono); font-size: 12px; color: var(--color-primary);" id="updateCountdownTimer">Reconnecting in: 15s</div>
            </div>

            <!-- Fallback Terminal Command Box -->
            <div>
              <label class="form-label" style="font-size: 12px;">Manual Terminal Update Command (Fallback):</label>
              <div class="input-row">
                <input type="text" id="manualUpdateCmdInput" class="text-input-styled" readonly value="docker compose pull && docker compose up -d">
                <button class="btn btn-secondary btn-sm" onclick="copyInput('manualUpdateCmdInput', 'Command copied!', this)">Copy</button>
              </div>
            </div>

            <!-- Footer Actions -->
            <div class="update-modal-footer" style="display: flex; gap: var(--space-sm); justify-content: space-between; align-items: center; margin-top: 4px;">
              <button class="btn btn-secondary btn-sm" onclick="checkSystemVersion(true)">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M21.34 15.57a10 10 0 1 1-.57-8.38l5.67-5.67"/></svg>
                <span>Re-check</span>
              </button>
              <div style="display: flex; gap: var(--space-sm);">
                <button class="btn btn-secondary" onclick="closeUpdateModal()">Close</button>
                <button class="btn btn-primary" id="btnExecuteUpdate" onclick="executeSystemUpdate()">
                  ⚡ Update Now (1-Click)
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Datalist for Group Suggestions -->
      <datalist id="groupSuggestions"></datalist>

      <!-- Group Management Modal -->
      <div id="groupModal" class="modal-overlay" onclick="closeOnBackdrop(event, 'groupModal')">
        <div class="modal-window" style="max-width: 560px;">
          <div class="modal-top">
            <div>
              <h3 style="display: flex; align-items: center; gap: 8px;">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
                <span>Manage Playlist Groups</span>
              </h3>
              <p style="font-size: 13px; color: var(--text-secondary); margin-top: 4px;">
                Create, rename, or delete category groups. Renaming cascades to member channels automatically.
              </p>
            </div>
            <button class="btn btn-secondary btn-xs" onclick="closeGroupModal()">✕</button>
          </div>

          <!-- Add Group Form -->
          <div style="display: flex; gap: 8px; margin-bottom: var(--space-md);">
            <input type="text" id="newGroupNameInput" class="form-control" placeholder="New group name (e.g. Documentaries, Sports 4K)" onkeydown="if(event.key==='Enter'){event.preventDefault(); createNewGroup();}">
            <button class="btn btn-primary btn-sm" onclick="createNewGroup()" style="white-space: nowrap;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              <span>Add Group</span>
            </button>
          </div>

          <!-- Existing Groups List -->
          <div id="groupManagerList" class="group-manager-list">
            <!-- Populated dynamically via renderGroupModalList() -->
          </div>

          <div style="display: flex; justify-content: flex-end; margin-top: var(--space-sm);">
            <button class="btn btn-secondary" onclick="closeGroupModal()">Close</button>
          </div>
        </div>
      </div>

      <!-- Floating Bulk Action Bar -->
      <div id="bulkActionBar" class="floating-bulk-bar">
        <span class="bulk-count-badge">
          <span id="bulkSelectedCount">0</span> selected
        </span>
        <div style="display: flex; align-items: center; gap: 6px;">
          <label style="font-size: 12px; color: var(--text-secondary); white-space: nowrap;">Move to:</label>
          <select id="bulkGroupSelect" class="bulk-select-group">
            <!-- Options populated dynamically -->
          </select>
          <button class="btn btn-primary btn-sm" onclick="executeBulkMove()">
            <span>Move</span>
          </button>
        </div>
        <button class="btn btn-destructive btn-sm" onclick="executeBulkDelete()" title="Delete selected channels">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
          <span>Delete</span>
        </button>
        <button class="btn btn-secondary btn-sm" onclick="clearSelection()" title="Clear selection">
          ✕
        </button>
      </div>

      <!-- Toast Shelf -->
      <div id="toastShelf" class="toast-shelf"></div>

      <script>
        let allChannels = #{channels_json};
        let allGroups = #{groups_json};
        let selectedChannelIds = new Set();
        const baseUrl = (typeof window !== "undefined" && window.location && window.location.origin) ? window.location.origin : "#{base_url}";
        let appSettings = #{Jason.encode!(%{auth_enabled: auth_enabled, auth_username: auth_user, auth_password: auth_pass, epg_url: epg_url})};
        let currentFilterGroup = "ALL";
        let currentFleetFilter = "all";
        let currentView = "grid";
        let hlsPlayerInstance = null;
        let activeWebPlayerUrl = "";
        let activeWebPlayerTitle = "";
        let activeWebPlayerTarget = "";
        let castSession = null;
        let isCastApiAvailable = false;
        let modalSourcesArray = [];
        let isManuallyEditingGroup = false;
        let isManuallyEditingCountry = false;

        function getLiveStreamUrl(target, isContentId = false) {
          if (appSettings && appSettings.auth_enabled && appSettings.auth_username && appSettings.auth_password) {
            return baseUrl + "/live/" + encodeURIComponent(appSettings.auth_username) + "/" + encodeURIComponent(appSettings.auth_password) + "/" + encodeURIComponent(target) + ".ts";
          } else {
            const param = isContentId ? "id=" : "channel=";
            return baseUrl + "/live?" + param + encodeURIComponent(target);
          }
        }

        function openWebPlayerForChannel(channelId) {
          const c = (allChannels || []).find(x => x.id === channelId);
          const name = c ? (c.name || "Channel") : "Channel";
          const hlsUrl = getCastStreamUrl(channelId);
          openWebPlayerModal(name, hlsUrl, channelId);
        }

        function openLauncherForChannel(channelId) {
          const c = (allChannels || []).find(x => x.id === channelId);
          const name = c ? (c.name || "Channel") : "Channel";
          const liveUrl = getLiveStreamUrl(channelId);
          openLauncherModal(name, liveUrl, channelId);
        }

        // DOM Elements
        const channelGrid = document.getElementById("channelGrid");
        const channelTableContainer = document.getElementById("channelTableContainer");
        const channelTable = document.getElementById("channelTable");
        const channelTableBody = document.getElementById("channelTableBody");
        const categoryTabs = document.getElementById("categoryTabs");
        const channelCountBadge = document.getElementById("channelCountBadge");

        // Utility String Escapers for Safe Dynamic HTML/Attribute Generation
        function escapeHtml(str) {
          if (!str && str !== 0) return "";
          return String(str)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#39;");
        }

        function escapeAttr(str) {
          if (!str && str !== 0) return "";
          return String(str)
            .replace(/"/g, "&quot;")
            .replace(/'/g, "\\'");
        }

        // Populate Group Datalist for Autocomplete & Bulk Select Dropdown
        function populateGroupDatalist() {
          const datalist = document.getElementById("groupSuggestions");
          const bulkSelect = document.getElementById("bulkGroupSelect");
          const groupMap = new Map();

          (allGroups || []).forEach(g => {
            groupMap.set(g.name, g);
          });
          (allChannels || []).forEach(c => {
            const name = (c.group && c.group.trim()) ? c.group.trim() : "General";
            if (!groupMap.has(name)) groupMap.set(name, { id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name: name, order: 999 });
          });

          const sortedGroups = Array.from(groupMap.values()).sort((a, b) => {
            if ((a.order || 999) !== (b.order || 999)) return (a.order || 999) - (b.order || 999);
            return (a.name || "").localeCompare(b.name || "");
          });

          if (datalist) {
            datalist.innerHTML = sortedGroups.map(g => `<option value="${escapeAttr(g.name)}"></option>`).join("");
          }

          if (bulkSelect) {
            bulkSelect.innerHTML = sortedGroups.map(g => `<option value="${escapeAttr(g.name)}">${escapeHtml(g.name)}</option>`).join("") + '<option value="__new__">+ New Group...</option>';
          }
        }

        // Render Category Tabs (StreamFlix Filter Chips with Manage Groups CTA)
        function renderCategoryTabs() {
          const groupMap = new Map();
          (allGroups || []).forEach(g => {
            groupMap.set(g.name, { id: g.id, name: g.name, order: g.order || 999 });
          });

          (allChannels || []).forEach(c => {
            const name = (c.group && c.group.trim()) ? c.group.trim() : "General";
            if (!groupMap.has(name)) {
              groupMap.set(name, { id: name.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name: name, order: 999 });
            }
          });

          const sortedGroups = Array.from(groupMap.values()).sort((a, b) => {
            if ((a.order || 999) !== (b.order || 999)) return (a.order || 999) - (b.order || 999);
            return (a.name || "").localeCompare(b.name || "");
          });

          let html = `
            <button class="tab-btn ${currentFilterGroup === "ALL" ? "active" : ""}" onclick="selectCategory('ALL')">
              <span>All</span>
              <span style="opacity: 0.7; font-size: 12px;">(${(allChannels || []).length})</span>
            </button>
          `;

          sortedGroups.forEach(g => {
            const count = (allChannels || []).filter(c => (c.group || "General") === g.name).length;
            const activeClass = currentFilterGroup === g.name ? "active" : "";
            html += `
              <button class="tab-btn ${activeClass}" onclick="selectCategory('${escapeAttr(g.name)}')">
                <span>${escapeHtml(g.name)}</span>
                <span style="opacity: 0.7; font-size: 12px;">(${count})</span>
              </button>
            `;
          });

          html += `
            <button class="tab-btn" onclick="openGroupModal()" title="Manage Playlist Groups" style="border-style: dashed; margin-left: auto;">
              <span>📁 Manage Groups</span>
            </button>
          `;

          categoryTabs.innerHTML = html;
          populateGroupDatalist();
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

        // Render Channel Catalog (with Checkbox Selection & Interactive Quick Move Group Badges)
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
            updateBulkActionBar();
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
              const isSelected = selectedChannelIds.has(c.id);

              const sourcesListHtml = sources.map((s, idx) => `
                <div class="source-item" id="source-row-${c.id}-${idx}">
                  <span style="color: var(--color-primary); font-weight: 700;">#${idx + 1}</span>
                  <span style="flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${s}</span>
                  <span id="badge-${c.id}-${idx}" style="font-size: 11px;"></span>
                  <button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); copyText('${s}', 'Source hash copied!', this)">Copy</button>
                </div>
              `).join("");

              return `
                <div class="channel-card-sf ${isSelected ? 'selected' : ''}" data-id="${c.id}">
                  <!-- Multi-Select Checkbox -->
                  <div class="card-select-wrap" onclick="event.stopPropagation()">
                    <input type="checkbox" class="channel-checkbox" value="${c.id}" ${isSelected ? 'checked' : ''} onchange="toggleChannelSelection('${c.id}', this.checked)">
                  </div>

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
                      <span class="chip-filter chip-filter-interactive" onclick="event.stopPropagation(); quickChangeGroup('${c.id}', '${escapeAttr(c.group || 'General')}')" title="Click to move group">📁 ${escapeHtml(c.group || 'General')} ▾</span>
                      <span class="chip-status-success">🛡️ ${fallbackCount} sources</span>
                    </div>

                    <!-- Centered Hover Play CTA (Primary Red) -->
                    <button class="poster-play-btn" onclick="openLauncherForChannel('${c.id}')" title="Play">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
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
                          <button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); validateChannelSources('${c.id}')" title="Test source health" style="font-size: 10px; padding: 2px 6px;">🔍 Test</button>
                          ${fallbackCount > 1 ? `<button class="btn btn-secondary btn-xs" onclick="event.stopPropagation(); pruneDeadSources('${c.id}')" title="Prune dead sources" style="font-size: 10px; padding: 2px 6px; color: var(--color-danger);">🧹 Prune Dead</button>` : ''}
                        </div>
                        ${sourcesListHtml}
                      </div>
                    </div>

                    <!-- Card Action Bar (Dual Row Layout, Space-Optimized) -->
                    <div class="card-action-bar">
                      <!-- Row 1: Dual Primary Playback Actions (50/50 Grid) -->
                      <div class="card-play-btns">
                        <button class="btn btn-secondary btn-xs" onclick="openWebPlayerForChannel('${c.id}')" title="Preview live in browser">
                          <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                          <span>Preview</span>
                        </button>
                        <button class="btn btn-primary btn-xs" onclick="openLauncherForChannel('${c.id}')" title="Launch stream in VLC / IINA / PotPlayer">
                          <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                          <span>Watch</span>
                        </button>
                      </div>

                      <!-- Row 2: Secondary Utility Actions (Link, Edit, Delete) -->
                      <div class="card-tools-row">
                        <button class="card-tool-btn" onclick="copyText('${liveUrl}', 'Stream link copied!', this)" title="Copy stream URL">
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                          <span>Copy Link</span>
                        </button>
                        <div class="card-tool-icons">
                          <button class="card-icon-btn" onclick="editChannel('${c.id}')" title="Edit channel">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                          </button>
                          <button class="card-icon-btn card-icon-btn-danger" onclick="deleteChannel('${c.id}')" title="Delete channel">
                            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                          </button>
                        </div>
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
              const isSelected = selectedChannelIds.has(c.id);
              return `
                <tr data-id="${c.id}" class="${isSelected ? 'selected' : ''}">
                  <td style="width: 36px; text-align: center;" onclick="event.stopPropagation()">
                    <input type="checkbox" class="channel-checkbox" value="${c.id}" ${isSelected ? 'checked' : ''} onchange="toggleChannelSelection('${c.id}', this.checked)">
                  </td>
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
                  <td>
                    <span class="chip-filter chip-filter-interactive" onclick="event.stopPropagation(); quickChangeGroup('${c.id}', '${escapeAttr(c.group || 'General')}')" title="Click to move group">📁 ${escapeHtml(c.group || 'General')} ▾</span>
                  </td>
                  <td>
                    <div style="display: flex; align-items: center; gap: 4px;">
                      <span class="chip-status-success">🛡️ ${(c.sources || []).length} sources</span>
                      ${(c.sources || []).length > 1 ? `<button class="btn btn-ghost btn-xs" onclick="pruneDeadSources('${c.id}')" title="Prune dead sources" style="padding: 1px 4px; font-size: 11px; color: var(--color-danger);">🧹</button>` : ''}
                    </div>
                  </td>
                  <td style="text-align: right; white-space: nowrap;">
                    <div class="table-actions-group">
                      <button class="btn btn-secondary btn-xs" onclick="openWebPlayerForChannel('${c.id}')" title="Preview live in browser">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                        <span>Preview</span>
                      </button>
                      <button class="btn btn-primary btn-xs" onclick="openLauncherForChannel('${c.id}')" title="Launch stream in VLC / IINA / PotPlayer">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                        <span>Watch</span>
                      </button>
                      <button class="btn btn-ghost btn-icon btn-xs" onclick="copyText('${liveUrl}', 'Stream link copied!', this)" title="Copy stream link">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                      </button>
                      <button class="btn btn-ghost btn-icon btn-xs" onclick="editChannel('${c.id}')" title="Edit channel">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                      </button>
                      <button class="btn btn-destructive btn-icon btn-xs" onclick="deleteChannel('${c.id}')" title="Delete channel">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                      </button>
                    </div>
                  </td>
                </tr>
              `;
            }).join("");
          }

          updateBulkActionBar();
        }

        // Multi-Channel Selection & Floating Bulk Bar Handlers
        function toggleChannelSelection(id, isSelected) {
          if (isSelected) {
            selectedChannelIds.add(id);
          } else {
            selectedChannelIds.delete(id);
          }
          updateChannelSelectionUi(id, isSelected);
          updateBulkActionBar();
        }

        function updateChannelSelectionUi(id, isSelected) {
          const card = document.querySelector(`.channel-card-sf[data-id="${id}"]`);
          if (card) {
            if (isSelected) card.classList.add("selected");
            else card.classList.remove("selected");
            const chk = card.querySelector(".channel-checkbox");
            if (chk) chk.checked = isSelected;
          }
          const row = document.querySelector(`tr[data-id="${id}"]`);
          if (row) {
            if (isSelected) row.classList.add("selected");
            else row.classList.remove("selected");
            const chk = row.querySelector(".channel-checkbox");
            if (chk) chk.checked = isSelected;
          }
        }

        function toggleSelectAll(masterCheckbox) {
          const isChecked = masterCheckbox.checked;
          const currentVisible = getCurrentlyFilteredChannels();
          currentVisible.forEach(c => {
            if (isChecked) {
              selectedChannelIds.add(c.id);
            } else {
              selectedChannelIds.delete(c.id);
            }
            updateChannelSelectionUi(c.id, isChecked);
          });
          updateBulkActionBar();
        }

        function clearSelection() {
          selectedChannelIds.clear();
          document.querySelectorAll(".channel-card-sf.selected").forEach(el => el.classList.remove("selected"));
          document.querySelectorAll("tr.selected").forEach(el => el.classList.remove("selected"));
          document.querySelectorAll(".channel-checkbox").forEach(el => { el.checked = false; });
          const selectAll = document.getElementById("selectAllCheckbox");
          if (selectAll) {
            selectAll.checked = false;
            selectAll.indeterminate = false;
          }
          updateBulkActionBar();
        }

        function updateBulkActionBar() {
          const bar = document.getElementById("bulkActionBar");
          const countBadge = document.getElementById("bulkSelectedCount");
          const selectAll = document.getElementById("selectAllCheckbox");
          const count = selectedChannelIds.size;

          if (countBadge) countBadge.innerText = count;

          if (bar) {
            if (count > 0) {
              bar.classList.add("show");
            } else {
              bar.classList.remove("show");
            }
          }

          if (selectAll) {
            const visible = getCurrentlyFilteredChannels();
            const visibleSelected = visible.filter(c => selectedChannelIds.has(c.id)).length;
            if (visible.length > 0 && visibleSelected === visible.length) {
              selectAll.checked = true;
              selectAll.indeterminate = false;
            } else if (visibleSelected > 0) {
              selectAll.checked = false;
              selectAll.indeterminate = true;
            } else {
              selectAll.checked = false;
              selectAll.indeterminate = false;
            }
          }
        }

        function getCurrentlyFilteredChannels() {
          const q = document.getElementById("channelSearch") ? document.getElementById("channelSearch").value.toLowerCase().trim() : "";
          let filtered = allChannels || [];

          if (currentFilterGroup !== "ALL") {
            filtered = filtered.filter(c => (c.group || "General") === currentFilterGroup);
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
              (c.name || "").toLowerCase().includes(q) ||
              (c.country && c.country.toLowerCase().includes(q)) ||
              (c.group && c.group.toLowerCase().includes(q)) ||
              (c.id || "").toLowerCase().includes(q) ||
              (c.sources || []).some(s => s.toLowerCase().includes(q))
            );
          }
          return filtered;
        }

        // Bulk Actions Execution
        async function executeBulkMove() {
          const channelIds = Array.from(selectedChannelIds);
          if (channelIds.length === 0) {
            showToast("No channels selected", false);
            return;
          }

          const selectEl = document.getElementById("bulkGroupSelect");
          let targetGroup = selectEl ? selectEl.value : "";
          if (targetGroup === "__new__") {
            targetGroup = prompt("Enter new group name:");
            if (!targetGroup || !targetGroup.trim()) return;
            targetGroup = targetGroup.trim();
          }

          if (!targetGroup) return;

          try {
            const res = await fetch("/api/channels/bulk-move", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ channel_ids: channelIds, group: targetGroup })
            });
            const data = await res.json();
            if (res.ok && data.status === "ok") {
              const idSet = new Set(channelIds);
              allChannels = allChannels.map(c => {
                if (idSet.has(c.id)) {
                  return { ...c, group: targetGroup };
                }
                return c;
              });
              await refreshGroupsFromServer();
              clearSelection();
              filterChannels();
              showToast("Moved " + data.moved_count + " channels to '" + targetGroup + "'!");
            } else {
              showToast(data.error || "Failed to move channels", false);
            }
          } catch (err) {
            showToast("Bulk move error: " + err.message, false);
          }
        }

        async function executeBulkDelete() {
          const channelIds = Array.from(selectedChannelIds);
          if (channelIds.length === 0) {
            showToast("No channels selected", false);
            return;
          }

          if (!confirm("Are you sure you want to permanently delete " + channelIds.length + " selected channels?")) {
            return;
          }

          try {
            const res = await fetch("/api/channels/bulk-delete", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ channel_ids: channelIds })
            });
            const data = await res.json();
            if (res.ok && data.status === "ok") {
              const idSet = new Set(channelIds);
              allChannels = allChannels.filter(c => !idSet.has(c.id));
              clearSelection();
              await refreshGroupsFromServer();
              updateFleetHealthMetrics();
              filterChannels();
              showToast("Deleted " + data.deleted_count + " channels successfully!");
            } else {
              showToast(data.error || "Failed to delete channels", false);
            }
          } catch (err) {
            showToast("Bulk delete error: " + err.message, false);
          }
        }

        // Single-Channel Quick Group Reassignment
        async function quickChangeGroup(channelId, currentGroup) {
          const channel = allChannels.find(c => c.id === channelId);
          const channelName = channel ? channel.name : channelId;
          const groupNames = (allGroups || []).map(g => g.name);
          const promptMsg = "Move '" + channelName + "' to group:\\nAvailable groups: " + groupNames.join(", ") + "\\n(or type a new group name)";
          const newGroup = prompt(promptMsg, currentGroup || "General");

          if (!newGroup || !newGroup.trim() || newGroup.trim() === currentGroup) {
            return;
          }
          const targetGroup = newGroup.trim();

          try {
            const res = await fetch("/api/channels/" + encodeURIComponent(channelId) + "/group", {
              method: "PATCH",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ group: targetGroup })
            });
            const data = await res.json();
            if (res.ok && data.status === "ok") {
              const idx = allChannels.findIndex(c => c.id === channelId);
              if (idx !== -1) {
                allChannels[idx] = { ...allChannels[idx], group: targetGroup };
              }
              await refreshGroupsFromServer();
              filterChannels();
              showToast("Moved channel to '" + targetGroup + "'!");
            } else {
              showToast(data.error || "Failed to update channel group", false);
            }
          } catch (err) {
            showToast("Error updating group: " + err.message, false);
          }
        }

        // Group Management Modal Controllers
        function openGroupModal() {
          renderGroupModalList();
          document.getElementById("groupModal").classList.add("active");
          const input = document.getElementById("newGroupNameInput");
          if (input) {
            input.value = "";
            setTimeout(() => input.focus(), 100);
          }
        }

        function closeGroupModal() {
          document.getElementById("groupModal").classList.remove("active");
        }

        async function refreshGroupsFromServer() {
          try {
            const res = await fetch("/api/groups");
            if (res.ok) {
              allGroups = await res.json();
              renderCategoryTabs();
              populateGroupDatalist();
            }
          } catch (_) {}
        }

        function renderGroupModalList() {
          const container = document.getElementById("groupManagerList");
          if (!container) return;

          if (!allGroups || allGroups.length === 0) {
            container.innerHTML = '<div style="text-align: center; color: var(--text-tertiary); padding: 16px;">No groups found</div>';
            return;
          }

          const sorted = [...allGroups].sort((a, b) => ((a.order || 999) - (b.order || 999)));

          container.innerHTML = sorted.map(g => {
            const channelCount = (allChannels || []).filter(c => (c.group || "General") === g.name).length;
            const isDefault = g.name === "General";
            return `
              <div class="group-manager-item" data-group-id="${escapeAttr(g.id)}">
                <div class="group-manager-info">
                  <span class="group-manager-name">${escapeHtml(g.name)}</span>
                  <span class="group-channel-count">${channelCount} ${channelCount === 1 ? 'channel' : 'channels'}</span>
                </div>
                <div class="group-manager-actions">
                  <button class="btn btn-secondary btn-xs" onclick="startRenameGroup('${escapeAttr(g.id)}', '${escapeAttr(g.name)}')" title="Rename group">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                    <span>Rename</span>
                  </button>
                  ${isDefault ? `
                    <button class="btn btn-secondary btn-xs" disabled title="Default fallback group cannot be deleted" style="opacity: 0.4;">
                      <span>Delete</span>
                    </button>
                  ` : `
                    <button class="btn btn-destructive btn-xs" onclick="deleteGroup('${escapeAttr(g.id)}', '${escapeAttr(g.name)}', ${channelCount})" title="Delete group">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                      <span>Delete</span>
                    </button>
                  `}
                </div>
              </div>
            `;
          }).join("");
        }

        async function createNewGroup() {
          const input = document.getElementById("newGroupNameInput");
          if (!input) return;
          const name = input.value.trim();
          if (!name) {
            showToast("Please enter a group name", false);
            return;
          }

          try {
            const res = await fetch("/api/groups", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ name })
            });
            const data = await res.json();
            if (res.ok && (data.status === "ok" || data.status === "created")) {
              input.value = "";
              await refreshGroupsFromServer();
              renderGroupModalList();
              showToast("Group '" + data.group.name + "' created successfully!");
            } else {
              showToast(data.error || "Failed to create group", false);
            }
          } catch (err) {
            showToast("Error creating group: " + err.message, false);
          }
        }

        async function startRenameGroup(groupId, currentName) {
          const newName = prompt("Enter new name for group '" + currentName + "':", currentName);
          if (!newName || !newName.trim() || newName.trim() === currentName) return;

          const targetName = newName.trim();
          try {
            const res = await fetch("/api/groups/" + encodeURIComponent(groupId), {
              method: "PUT",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ name: targetName })
            });
            const data = await res.json();
            if (res.ok && (data.status === "ok" || data.status === "updated")) {
              allChannels = allChannels.map(c => {
                if ((c.group || "General") === currentName) {
                  return { ...c, group: targetName };
                }
                return c;
              });
              if (currentFilterGroup === currentName) {
                currentFilterGroup = targetName;
              }
              await refreshGroupsFromServer();
              renderGroupModalList();
              filterChannels();
              showToast("Renamed group to '" + targetName + "' (updated member channels)!");
            } else {
              showToast(data.error || "Failed to rename group", false);
            }
          } catch (err) {
            showToast("Error renaming group: " + err.message, false);
          }
        }

        async function deleteGroup(groupId, groupName, channelCount = 0) {
          let fallbackGroup = "General";
          let confirmMsg = "Are you sure you want to delete group '" + groupName + "'?";
          if (channelCount > 0) {
            confirmMsg += "\\nIts " + channelCount + " channels will be safely moved to '" + fallbackGroup + "'.";
          }
          if (!confirm(confirmMsg)) return;

          try {
            const res = await fetch("/api/groups/" + encodeURIComponent(groupId) + "?fallback_group=" + encodeURIComponent(fallbackGroup), {
              method: "DELETE"
            });
            const data = await res.json();
            if (res.ok && (data.status === "ok" || data.status === "deleted")) {
              allChannels = allChannels.map(c => {
                if (c.group === groupName) {
                  return { ...c, group: fallbackGroup };
                }
                return c;
              });
              if (currentFilterGroup === groupName) {
                currentFilterGroup = "ALL";
              }
              await refreshGroupsFromServer();
              renderGroupModalList();
              filterChannels();
              showToast("Deleted group '" + groupName + "' successfully!");
            } else {
              showToast(data.error || "Failed to delete group", false);
            }
          } catch (err) {
            showToast("Error deleting group: " + err.message, false);
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
          if (!confirm("This will scan and prune dead Content IDs across all multi-source channels (single-source channels remain safe). Continue?")) {
            return;
          }
          const origText = btn ? btn.innerHTML : "";
          if (btn) {
            btn.disabled = true;
            btn.innerHTML = "<span>⏳ Scanning all channels...</span>";
          }
          showToast("Scanning and pruning dead sources across all channels...", true);

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
              showToast("Pruning completed: Removed " + (data.pruned_sources_count || 0) + " dead sources!", true);
            } else {
              showToast(data.error || "Failed to prune dead sources across all channels.", false);
            }
          } catch (err) {
            showToast("Connection error while pruning: " + err.message, false);
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
          const streamUrl = getLiveStreamUrl(clean, true);
          openLauncherModal("Quick Stream (" + clean.substring(0, 8) + "...)", streamUrl, clean);
        }

        function copyQuickStreamUrl(btn = null) {
          const val = document.getElementById("quickTestInput").value.trim();
          const clean = extractCleanHash(val);
          if (!clean) {
            showToast("Please enter a valid Content ID to copy link!", false);
            return;
          }
          const url = getLiveStreamUrl(clean, true);
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
          if (/\b(sport|sports|football|soccer|golf|tennis|f1|racing|nba|premier|serie|bundesliga|ufc|boxing)\b/i.test(v)) {
            detectedGroup = "Sports";
          } else if (/\b(movie|movies|cinema|cine|hbo|cinemax|film)\b/i.test(v)) {
            detectedGroup = "Movies";
          } else if (/\b(news|cnn|bbc news)\b/i.test(v)) {
            detectedGroup = "News";
          } else if (/\b(music|mtv)\b/i.test(v)) {
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
            const rankLabel = isPrimary ? "#1 (Primary)" : ("#" + (idx + 1) + " (Backup)");
            const shortHash = src.slice(0, 8) + "..." + src.slice(-6);
            const canUp = idx > 0;
            const canDown = idx < modalSourcesArray.length - 1;

            return `
              <div class="source-card-item">
                <span class="source-card-rank ${isPrimary ? 'rank-primary' : 'rank-backup'}">${rankLabel}</span>
                <span class="source-card-hash" title="${src}"><code>${shortHash}</code></span>
                <div class="source-card-actions">
                  <button type="button" class="source-card-btn" onclick="moveModalSourceUp(${idx})" ${canUp ? '' : 'disabled'} title="Increase priority">▲</button>
                  <button type="button" class="source-card-btn" onclick="moveModalSourceDown(${idx})" ${canDown ? '' : 'disabled'} title="Decrease priority">▼</button>
                  <button type="button" class="source-card-btn btn-remove" onclick="removeModalSource(${idx})" title="Remove source">✕</button>
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
              showToast("Clipboard reading not supported by your browser. Please paste manually into the textarea below.", false);
              return;
            }
            const text = await navigator.clipboard.readText();
            const matches = (text.match(/[a-fA-F0-9]{40}/g) || []);
            if (matches.length === 0) {
              showToast("No valid 40-character hex Content IDs found in clipboard!", false);
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
            showToast("Extracted & pasted " + matches.length + " Content IDs (" + addedCount + " new sources) from clipboard!", true);
          } catch (err) {
            showToast("Failed to read clipboard: " + err.message, false);
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
          if (testBtn) { testBtn.disabled = false; testBtn.innerText = "🔍 Test Sources"; }

          modal.classList.add("active");
          document.getElementById("inputName").focus();
        }

        async function testModalSources() {
          const val = document.getElementById("inputSources").value;
          const matches = val.match(/[a-fA-F0-9]{40}/g) || [];
          const resBox = document.getElementById("modalValidationResults");
          const btn = document.getElementById("btnTestModalSources");
          if (matches.length === 0) {
            showToast("Please enter at least 1 Content ID (40 hex characters)!", false);
            return;
          }
          btn.disabled = true;
          btn.innerText = "⏳ Testing...";
          resBox.style.display = "block";
          resBox.innerHTML = '<div style="font-size: 12px; color: var(--text-secondary);"><span class="live-dot" style="animation: pulse 1s infinite;"></span> Testing ' + matches.length + ' sources via AceStream Engine...</div>';

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
                results.push({ source: src, valid: false, error: data.error || "Connection error" });
              }
            } catch (err) {
              results.push({ source: src, valid: false, error: err.message });
            }
          }

          btn.disabled = false;
          btn.innerText = "🔍 Test Sources";

          const deadCount = results.filter(r => !r.valid).length;
          let html = '<div style="background: var(--surface-card); border: 1px solid var(--border-default); border-radius: var(--radius-sm); padding: 8px; font-size: 12px; max-height: 140px; overflow-y: auto;">';
          results.forEach((r, idx) => {
            const shortHash = r.source.slice(0, 8) + '...' + r.source.slice(-6);
            if (r.valid) {
              html += '<div style="display: flex; justify-content: space-between; align-items: center; padding: 2px 0; color: var(--color-success);">' +
                '<span>🟢 #' + (idx+1) + ' <code>' + shortHash + '</code></span>' +
                '<span style="font-size: 11px; opacity: 0.8;">Alive (' + (r.response_time_ms || 0) + 'ms)</span></div>';
            } else {
              html += '<div style="display: flex; justify-content: space-between; align-items: center; padding: 2px 0; color: var(--color-danger);">' +
                '<span>🔴 #' + (idx+1) + ' <code>' + shortHash + '</code></span>' +
                '<span style="font-size: 11px; opacity: 0.9;">' + (r.error || 'Dead') + '</span></div>';
            }
          });

          if (deadCount > 0 && matches.length > 1) {
            const deadHashesJson = JSON.stringify(results.filter(r => !r.valid).map(r => r.source)).replace(/"/g, '&quot;');
            html += '<div style="margin-top: 6px; padding-top: 6px; border-top: 1px solid var(--border-subtle); display: flex; justify-content: flex-end;">' +
              '<button type="button" class="btn btn-destructive btn-xs" onclick="stripDeadModalSources(' + deadHashesJson + ')" style="font-size: 11px; padding: 2px 8px;">🧹 Remove ' + deadCount + ' dead sources</button></div>';
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
          showToast("Removed " + deadList.length + " dead sources from list!", true);
        }

        async function validateChannelSources(channelId) {
          const arrow = document.getElementById("arrow-" + channelId);
          const list = document.getElementById("sources-" + channelId);
          if (list && !list.classList.contains("show")) {
            list.classList.add("show");
            if (arrow) arrow.innerText = "▲";
          }
          showToast("Testing sources health...", true);

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
                    badge.innerHTML = '<span style="color: var(--color-success); font-weight: 600;">🟢 Alive (' + (r.response_time_ms || 0) + 'ms)</span>';
                  } else {
                    badge.innerHTML = '<span style="color: var(--color-danger); font-weight: 600;">🔴 Dead</span>';
                  }
                }
              });
              showToast("Validation complete: " + data.report.alive_count + " alive, " + data.report.dead_count + " dead.", data.report.dead_count === 0);
            }
          } catch (err) {
            showToast("Error testing sources: " + err.message, false);
          }
        }

        async function pruneDeadSources(channelId) {
          const c = allChannels.find(x => x.id === channelId);
          const name = c ? c.name : channelId;
          if (!confirm("Are you sure you want to test and prune dead sources for channel '" + name + "'?")) return;

          showToast("Testing and pruning dead sources...", true);
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
              showToast("Successfully pruned " + data.pruned_count + " dead sources!", true);
            } else {
              showToast(data.error || "Failed to prune dead sources.", false);
            }
          } catch (err) {
            showToast("Pruning error: " + err.message, false);
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
              await refreshGroupsFromServer();
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
              if (selectedChannelIds.has(id)) {
                selectedChannelIds.delete(id);
                updateBulkActionBar();
              }
              await refreshGroupsFromServer();
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
                await refreshGroupsFromServer();
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

        // In-Dashboard Web Video Player Modal (HLS Live Player)
        function openWebPlayerModal(title, streamUrl, target = "") {
          activeWebPlayerTitle = title;
          activeWebPlayerTarget = target || "";

          // Ensure streamUrl is always the HLS playlist endpoint (/cast/:target/live.m3u8)
          const hlsUrl = (target ? getCastStreamUrl(target) : streamUrl) || "";
          activeWebPlayerUrl = hlsUrl;

          const titleEl = document.getElementById("webPlayerChannelName");
          if (titleEl) titleEl.innerText = title;
          const modal = document.getElementById("webPlayerModal");
          if (modal) modal.classList.add("active");

          const videoElem = document.getElementById("webVideoPlayer");
          const statsBadge = document.getElementById("playerStatsBadge");
          const castBadge = document.getElementById("playerCastBadge");

          // Reset existing Hls player instance cleanly
          if (hlsPlayerInstance) {
            try {
              hlsPlayerInstance.stopLoad();
              hlsPlayerInstance.detachMedia();
              hlsPlayerInstance.destroy();
            } catch (_) {}
            hlsPlayerInstance = null;
          }

          if (videoElem) {
            videoElem.pause();
            videoElem.removeAttribute("src");
            videoElem.load();
          }

          // Manage Cast Badge state
          if (castSession && activeWebPlayerTarget) {
            if (castBadge) castBadge.style.display = "inline-flex";
            if (statsBadge) statsBadge.innerText = "Casting to TV";
          } else {
            if (castBadge) castBadge.style.display = "none";
          }

          if (window.Hls && Hls.isSupported()) {
            if (statsBadge) statsBadge.innerText = "HLS Connecting...";
            try {
              hlsPlayerInstance = new Hls({
                enableWorker: true,
                lowLatencyMode: true,
                backBufferLength: 30,
                maxBufferLength: 10,
                maxMaxBufferLength: 20
              });

              hlsPlayerInstance.loadSource(hlsUrl);
              hlsPlayerInstance.attachMedia(videoElem);

              hlsPlayerInstance.on(Hls.Events.MANIFEST_PARSED, () => {
                if (statsBadge) statsBadge.innerText = "HLS Live";
                const p = videoElem.play();
                if (p && p.catch) {
                  p.catch(err => {
                    console.log("Autoplay blocked or waiting user gesture:", err);
                  });
                }
              });

              hlsPlayerInstance.on(Hls.Events.FRAG_LOADED, (event, data) => {
                if (data && data.stats && statsBadge) {
                  const bw = data.stats.total && data.stats.loading.end ? Math.round((data.stats.total / 1024) / Math.max(0.1, (data.stats.loading.end - data.stats.loading.start) / 1000)) : 0;
                  if (bw > 0) {
                    statsBadge.innerText = "HLS: " + bw + " KB/s";
                  } else {
                    statsBadge.innerText = "HLS Live";
                  }
                }
              });

              hlsPlayerInstance.on(Hls.Events.ERROR, (event, data) => {
                console.warn("HLS Error:", data.type, data.details);
                if (data.fatal) {
                  switch (data.type) {
                    case Hls.ErrorTypes.NETWORK_ERROR:
                      if (statsBadge) statsBadge.innerText = "HLS: Network Error, retrying...";
                      hlsPlayerInstance.startLoad();
                      break;
                    case Hls.ErrorTypes.MEDIA_ERROR:
                      if (statsBadge) statsBadge.innerText = "HLS: Media Error, recovering...";
                      hlsPlayerInstance.recoverMediaError();
                      break;
                    default:
                      if (statsBadge) statsBadge.innerText = "HLS: " + data.details;
                      hlsPlayerInstance.destroy();
                      hlsPlayerInstance = null;
                      break;
                  }
                }
              });
            } catch (err) {
              console.warn("Hls initialization error:", err);
              if (statsBadge) statsBadge.innerText = "Direct Stream";
              if (videoElem) {
                videoElem.src = hlsUrl;
                videoElem.play().catch(() => {});
              }
            }
          } else if (videoElem && videoElem.canPlayType("application/vnd.apple.mpegurl")) {
            // Safari / iOS Native HLS playback
            if (statsBadge) statsBadge.innerText = "HLS Native";
            videoElem.src = hlsUrl;
            videoElem.play().catch(() => {});
          } else {
            if (statsBadge) statsBadge.innerText = "Native Video Fallback";
            if (videoElem) {
              videoElem.src = hlsUrl;
              videoElem.play().catch(() => {});
            }
          }
        }

        function closeWebPlayerModal() {
          const modal = document.getElementById("webPlayerModal");
          if (modal) modal.classList.remove("active");

          const videoElem = document.getElementById("webVideoPlayer");
          if (hlsPlayerInstance) {
            try {
              hlsPlayerInstance.stopLoad();
              hlsPlayerInstance.detachMedia();
              hlsPlayerInstance.destroy();
            } catch (_) {}
            hlsPlayerInstance = null;
          }

          if (videoElem) {
            videoElem.pause();
            videoElem.removeAttribute("src");
            videoElem.load();
          }
        }

        function openExternalFromWebPlayer() {
          const liveUrl = activeWebPlayerTarget ? getLiveStreamUrl(activeWebPlayerTarget) : activeWebPlayerUrl;
          const target = activeWebPlayerTarget;
          const title = activeWebPlayerTitle;
          closeWebPlayerModal();
          openLauncherModal(title, liveUrl, target);
        }

        // --- Google Cast (Chromecast / Google TV) Support ---
        function initGoogleCastFramework() {
          if (!window.cast || !window.cast.framework || !cast.framework.CastContext) return;
          try {
            cast.framework.CastContext.getInstance().setOptions({
              receiverApplicationId: chrome.cast.media.DEFAULT_MEDIA_RECEIVER_APP_ID,
              autoJoinPolicy: chrome.cast.AutoJoinPolicy.TAB_AND_ORIGIN_SCOPED
            });

            const context = cast.framework.CastContext.getInstance();
            context.addEventListener(
              cast.framework.CastContextEventType.SESSION_STATE_CHANGED,
              function(event) {
                switch (event.sessionState) {
                  case cast.framework.SessionState.SESSION_STARTED:
                  case cast.framework.SessionState.SESSION_RESUMED:
                    castSession = context.getCurrentSession();
                    onCastSessionConnected();
                    break;
                  case cast.framework.SessionState.SESSION_ENDED:
                    castSession = null;
                    onCastSessionDisconnected();
                    break;
                }
              }
            );

            context.addEventListener(
              cast.framework.CastContextEventType.CAST_STATE_CHANGED,
              function(event) {
                updateCastUiState(event.castState);
              }
            );
            isCastApiAvailable = true;
          } catch (e) {
            console.warn("Cast framework init error:", e);
          }
        }

        if (window.isCastApiAvailable || (window.cast && window.cast.framework)) {
          initGoogleCastFramework();
        }

        function warnIfLocalhostForCast() {
          const host = window.location.hostname;
          if (host === "localhost" || host === "127.0.0.1") {
            showToast("Notice: Chromecast requires accessing this dashboard via your server LAN IP (e.g. 192.168.x.x), not localhost.", false);
          }
        }

        function getCastStreamUrl(target) {
          const host = window.location.hostname;
          const port = window.location.port ? (":" + window.location.port) : "";
          const proto = window.location.protocol;

          let castUrl = proto + "//" + host + port + "/cast/" + encodeURIComponent(target) + "/live.m3u8";
          if (appSettings && appSettings.auth_enabled && appSettings.auth_username && appSettings.auth_password) {
            castUrl += "?username=" + encodeURIComponent(appSettings.auth_username) + "&password=" + encodeURIComponent(appSettings.auth_password);
          }
          return castUrl;
        }

        function updateCastUiState(castState) {
          const btn = document.getElementById("castLauncherBtn");
          const btnText = document.getElementById("castBtnText");
          if (!btn || !btnText) return;

          if (castState === cast.framework.CastState.CONNECTED) {
            const devName = (castSession && castSession.getCastDevice()) ? castSession.getCastDevice().friendlyName : "TV";
            btnText.innerText = "Casting: " + devName;
            btn.classList.add("btn-primary");
            btn.classList.remove("btn-secondary");
          } else {
            btnText.innerText = "Cast to TV";
            btn.classList.remove("btn-primary");
            btn.classList.add("btn-secondary");
          }
        }

        function triggerCast() {
          warnIfLocalhostForCast();

          if (!isCastApiAvailable && window.cast && window.cast.framework) {
            initGoogleCastFramework();
          }

          if (!isCastApiAvailable && !window.isCastApiAvailable && (!window.cast || !window.cast.framework)) {
            showToast("Google Cast requires Google Chrome or Edge on the same local Wi-Fi / LAN. Or use 'Copy Cast URL' with any player.", false);
            return;
          }
          if (!activeWebPlayerTarget) {
            showToast("Please select a channel to cast.", false);
            return;
          }
          try {
            cast.framework.CastContext.getInstance().requestSession();
          } catch (err) {
            console.log("Cast requestSession notice:", err);
          }
        }

        function onCastSessionConnected() {
          const badge = document.getElementById("playerCastBadge");
          const statsBadge = document.getElementById("playerStatsBadge");
          const videoElem = document.getElementById("webVideoPlayer");

          if (badge) badge.style.display = "inline-flex";
          if (statsBadge) statsBadge.innerText = "Casting to TV";

          // Pause local browser playback when streaming to TV to reduce CPU & network usage
          if (videoElem) {
            try { videoElem.pause(); } catch (_) {}
          }

          loadActiveChannelToCast();
        }

        function loadActiveChannelToCast() {
          if (!castSession || !activeWebPlayerTarget) return;

          const streamUrl = getCastStreamUrl(activeWebPlayerTarget);
          const mediaInfo = new chrome.cast.media.MediaInfo(streamUrl, "application/x-mpegURL");
          mediaInfo.streamType = chrome.cast.media.StreamType.LIVE;
          mediaInfo.metadata = new chrome.cast.media.GenericMediaMetadata();
          mediaInfo.metadata.title = activeWebPlayerTitle || "Live TV";
          mediaInfo.metadata.subtitle = "AcexGateway ⚡ Chromecast HLS";

          const request = new chrome.cast.media.LoadRequest(mediaInfo);
          request.autoplay = true;

          castSession.loadMedia(request).then(
            function() {
              const devName = (castSession && castSession.getCastDevice()) ? castSession.getCastDevice().friendlyName : "TV";
              showToast("Streaming live to " + devName, true);
              const btnText = document.getElementById("castBtnText");
              if (btnText) btnText.innerText = "Casting: " + devName;
            },
            function(errorCode) {
              console.warn("Cast media load error:", errorCode);
              showToast("Chromecast load error (" + errorCode + "). Ensure server LAN IP is reachable from TV.", false);
            }
          );
        }

        function onCastSessionDisconnected() {
          const badge = document.getElementById("playerCastBadge");
          const btnText = document.getElementById("castBtnText");
          const btn = document.getElementById("castLauncherBtn");

          if (badge) badge.style.display = "none";
          if (btnText) btnText.innerText = "Cast to TV";
          if (btn) {
            btn.classList.remove("btn-primary");
            btn.classList.add("btn-secondary");
          }

          // Resume local playback if player modal is still open
          const modal = document.getElementById("webPlayerModal");
          if (modal && modal.classList.contains("active") && activeWebPlayerUrl) {
            openWebPlayerModal(activeWebPlayerTitle, activeWebPlayerUrl, activeWebPlayerTarget);
          }
        }

        // Stream Launcher Modal
        function openLauncherModal(title, streamUrl, target = "") {
          document.getElementById("launcherModalTitle").innerText = title;
          document.getElementById("launcherStreamUrl").value = streamUrl;

          const castUrl = target ? getCastStreamUrl(target) : "";
          const castInput = document.getElementById("launcherCastUrl");
          if (castInput) {
            castInput.value = castUrl;
          }

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
          copyText(url, "Direct MPEG-TS URL copied!", btn);
        }

        function copyLauncherCastUrl(btn = null) {
          const url = document.getElementById("launcherCastUrl").value;
          if (!url || !url.trim()) {
            showToast("Chromecast HLS URL is empty!", false);
            return;
          }
          warnIfLocalhostForCast();
          copyText(url, "Chromecast HLS URL copied!", btn);
        }

        function copyWebPlayerCastUrl(btn = null) {
          if (!activeWebPlayerTarget) {
            showToast("No active channel target selected!", false);
            return;
          }
          warnIfLocalhostForCast();
          const url = getCastStreamUrl(activeWebPlayerTarget);
          copyText(url, "Chromecast HLS URL copied!", btn);
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

        let activePlaylistFormat = "hls";

        function switchPlaylistFormat(format) {
          activePlaylistFormat = format;
          const hlsBtn = document.getElementById("formatHlsBtn");
          const tsBtn = document.getElementById("formatTsBtn");

          if (format === "hls") {
            if (hlsBtn) hlsBtn.className = "btn btn-sm btn-primary";
            if (tsBtn) tsBtn.className = "btn btn-sm btn-secondary";
          } else {
            if (hlsBtn) hlsBtn.className = "btn btn-sm btn-secondary";
            if (tsBtn) tsBtn.className = "btn btn-sm btn-primary";
          }

          if (appSettings) {
            updateAuthDependentLinks(appSettings);
          }
        }

        function updateAuthDependentLinks(settings) {
          const isAuth = settings.auth_enabled;
          const user = settings.auth_username || "";
          const pass = settings.auth_password || "";

          let m3uUrl = "";
          if (activePlaylistFormat === "hls") {
            if (isAuth && user && pass) {
              m3uUrl = baseUrl + "/hls/" + encodeURIComponent(user) + "/" + encodeURIComponent(pass) + ".m3u8";
            } else {
              m3uUrl = baseUrl + "/hls.m3u8";
            }
          } else {
            if (isAuth && user && pass) {
              m3uUrl = baseUrl + "/ts/" + encodeURIComponent(user) + "/" + encodeURIComponent(pass) + ".m3u8";
            } else {
              m3uUrl = baseUrl + "/ts.m3u8";
            }
          }

          const m3uInput = document.getElementById("m3uUrlInput");
          if (m3uInput) m3uInput.value = m3uUrl;

          const downloadLink = document.getElementById("m3uDownloadLink");
          if (downloadLink) {
            downloadLink.href = m3uUrl;
            downloadLink.download = (activePlaylistFormat === "hls") ? "acex_hls_playlist.m3u8" : "acex_ts_playlist.m3u8";
            const downloadText = downloadLink.querySelector("span");
            if (downloadText) downloadText.innerText = (activePlaylistFormat === "hls") ? "Download HLS" : "Download TS";
          }

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
                badgeText.innerHTML = "🚀 New version: v" + data.latest_version;
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
            if (modalNotes) modalNotes.innerText = data.release_notes || "No release notes available.";
            if (modalLink && data.release_url) modalLink.href = data.release_url;

            if (modalBadge) {
              if (data.has_update) {
                modalBadge.innerText = "Update available 🚀";
                modalBadge.style.background = "rgba(225, 29, 72, 0.2)";
                modalBadge.style.color = "#FF5A79";
              } else {
                modalBadge.innerText = "Up to date ✓";
                modalBadge.style.background = "rgba(16, 185, 129, 0.15)";
                modalBadge.style.color = "#10B981";
              }
            }

            if (btnExec) {
              if (data.has_update) {
                btnExec.innerHTML = "⚡ Update to v" + data.latest_version + " (1-Click)";
              } else {
                btnExec.innerHTML = "⚡ Re-pull & Recreate Containers";
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
            checkSystemVersion(true);
          }
        }

        function closeUpdateModal() {
          const modal = document.getElementById("updateModal");
          if (modal) modal.classList.remove("active");
        }

        async function executeSystemUpdate() {
          const targetVer = (currentSystemVersionInfo && currentSystemVersionInfo.latest_version) ? currentSystemVersionInfo.latest_version : "";
          const confirmMsg = targetVer
            ? "Start updating system to version v" + targetVer + "? Containers will pull new images and restart."
            : "Start updating system? Containers will pull new images and restart.";

          if (!confirm(confirmMsg)) return;

          const btnExec = document.getElementById("btnExecuteUpdate");
          const progressBox = document.getElementById("updateProgressBox");
          const progressText = document.getElementById("updateProgressText");
          const countdown = document.getElementById("updateCountdownTimer");

          if (btnExec) {
            btnExec.disabled = true;
            btnExec.innerText = "Triggering update...";
          }

          if (progressBox) progressBox.style.display = "block";
          if (progressText) progressText.innerText = "Sending update command to server...";

          try {
            const resp = await fetch("/api/system/update", { method: "POST" });
            const data = await resp.json();

            if (resp.ok && (data.status === "updating" || data.status === "ok")) {
              if (progressText) progressText.innerText = data.message || "Update command dispatched! Waiting for containers to recreate...";
              pollServerReboot(targetVer);
            } else if (data.status === "manual_required" || data.command) {
              if (progressBox) progressBox.style.display = "none";
              if (btnExec) {
                btnExec.disabled = false;
                btnExec.innerText = "Manual Update";
              }
              showToast("System requires manual command execution via terminal.", false);
            } else {
              throw new Error(data.message || data.error || "Update trigger failed");
            }
          } catch (err) {
            const isNetworkDrop = err && (err.name === "TypeError" || String(err.message).includes("Failed to fetch") || String(err.message).includes("NetworkError"));
            if (isNetworkDrop) {
              if (progressText) progressText.innerText = "Server restarted for container recreation. Reconnecting...";
              pollServerReboot(targetVer);
            } else {
              if (progressBox) progressBox.style.display = "none";
              if (btnExec) {
                btnExec.disabled = false;
                btnExec.innerText = "⚡ Retry";
              }
              showToast("Failed to trigger update: " + err.message, false);
            }
          }
        }

        function pollServerReboot(targetVer) {
          let elapsedSeconds = 0;
          let serverWentOffline = false;
          const countdown = document.getElementById("updateCountdownTimer");
          const progressText = document.getElementById("updateProgressText");

          if (updateRebootInterval) clearInterval(updateRebootInterval);

          updateRebootInterval = setInterval(async () => {
            elapsedSeconds += 2;
            if (countdown) {
              countdown.innerText = "Elapsed: " + elapsedSeconds + "s (pulling image & recreating)";
            }

            try {
              const check = await fetch("/health?t=" + Date.now(), { cache: "no-store" });
              if (check.ok) {
                // If the container went offline and is now back up, or if sufficient time has elapsed
                if (serverWentOffline || elapsedSeconds >= 20) {
                  try {
                    const verRes = await fetch("/api/system/version?t=" + Date.now(), { cache: "no-store" });
                    if (verRes.ok) {
                      const verData = await verRes.json();
                      if (!targetVer || verData.current_version === targetVer || serverWentOffline) {
                        clearInterval(updateRebootInterval);
                        updateRebootInterval = null;
                        if (progressText) progressText.innerText = "✓ Update completed (v" + verData.current_version + ")! Reloading...";
                        showToast("System successfully updated to v" + verData.current_version + "!", true);
                        setTimeout(() => {
                          window.location.reload();
                        }, 1200);
                        return;
                      }
                    }
                  } catch (_) {}
                }
              }
            } catch (_) {
              serverWentOffline = true;
              if (progressText) progressText.innerText = "Container restarting with new image...";
            }

            if (elapsedSeconds >= 120) {
              clearInterval(updateRebootInterval);
              updateRebootInterval = null;
              if (progressText) {
                progressText.innerHTML = "Update is taking longer than expected. <br><button class='btn btn-primary btn-sm' onclick='window.location.reload()' style='margin-top:8px;'>Reload Page Now</button>";
              }
            }
          }, 2000);
        }

        // Realtime Stats Processing
        function applyStatsUpdate(data) {
          if (!data) return;

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
        }

        // Live EventStream (SSE) with Fallback Polling
        let sseSource = null;
        let fallbackPollingInterval = null;

        function connectLiveStats() {
          if (typeof EventSource !== "undefined") {
            try {
              if (sseSource) sseSource.close();
              sseSource = new EventSource("/api/live-stats");

              sseSource.onmessage = (event) => {
                try {
                  const data = JSON.parse(event.data);
                  applyStatsUpdate(data);
                } catch (_) {}
              };

              sseSource.onerror = () => {
                // If SSE fails or disconnects, temporarily fallback to polling until reconnect
                startFallbackPolling();
              };

              sseSource.onopen = () => {
                if (fallbackPollingInterval) {
                  clearInterval(fallbackPollingInterval);
                  fallbackPollingInterval = null;
                }
              };
              return;
            } catch (_) {}
          }

          startFallbackPolling();
        }

        async function pollStatsOnce() {
          try {
            const res = await fetch("/stat");
            if (res.ok) {
              const data = await res.json();
              applyStatsUpdate(data);
            }
          } catch (_) {}
        }

        function startFallbackPolling() {
          if (!fallbackPollingInterval) {
            fallbackPollingInterval = setInterval(pollStatsOnce, 4000);
          }
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
            closeGroupModal();
          }
        });

        // Initialize
        renderCategoryTabs();
        updateFleetHealthMetrics();
        renderChannels(allChannels);
        connectLiveStats();
        pollStatsOnce();
        checkSystemVersion();
      </script>
    </body>
    </html>
    """
  end
end
