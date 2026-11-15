// The eight widgets as the main page draws them, for the prototype.
const icon = (name) => `<svg data-icon="${name}"></svg>`;

export const widgets = [
  {
    key: "files", icon: "folder", name: "Files", line: "Your Desktop and pinned folders, opened in place.",
    html: `<h3>${icon("folder")}Files<a>Show all folders</a></h3>
      <ul class="rows"><li><b class="fold"></b>Desktop<i>38</i></li><li><b class="fold"></b>Documents<i>29</i></li>
      <li><b class="fold"></b>Downloads<i>14</i></li><li><b class="fold"></b>Pictures<i>6</i></li></ul>`,
  },
  {
    key: "calendar", icon: "calendar", name: "Calendar", line: "Today and tomorrow, in your calendars' colours.",
    html: `<h3>${icon("calendar")}Calendar<em>3</em></h3>
      <ul class="rows events"><li><b style="--c:#ff9f0a"></b>Design review<i>10:30</i></li>
      <li><b style="--c:#6c93ff"></b>Lunch at the harbour<i>13:00</i></li>
      <li><b style="--c:#30d158"></b>Flight to Lisbon<i>Tomorrow · 07:15</i></li></ul>`,
  },
  {
    key: "reminders", icon: "checklist", name: "Reminders", line: "What is still open. Tick one off right here.",
    html: `<h3>${icon("checklist")}Reminders<em>3</em></h3>
      <ul class="rows todo"><li><b></b>Renew the passport<i>18 Nov</i></li><li><b></b>Send the invoice<i>20 Nov</i></li>
      <li><b></b>Water the plants</li></ul>`,
  },
  {
    key: "mail", icon: "mail", name: "Mail", line: "The newest messages from every inbox.",
    html: `<h3>${icon("mail")}Mail<em>2</em></h3>
      <ul class="rows mail"><li class="unread"><b></b>Your tickets for Friday<i>Box office</i></li>
      <li class="unread"><b></b>Invoice 0142 is paid<i>Billing</i></li><li><b></b>Notes from Tuesday<i>Studio</i></li>
      <li><b></b>The week in type<i>Newsletter</i></li></ul>`,
  },
  {
    key: "playing", icon: "music", name: "Now playing", line: "Whatever is playing in any app, with controls.",
    html: `<h3>${icon("music")}Now playing</h3>
      <div class="playing"><span class="cover"></span><div><strong>Low Tide</strong><small>Halden · Music</small>
      <span class="controls"><i>${icon("arrowLeft")}</i><b>${icon("pause")}</b><i>${icon("arrowRight")}</i></span></div></div>`,
  },
  {
    key: "weather", icon: "sunCloud", name: "Weather", line: "Now, and the next four days, where you are.",
    html: `<h3>${icon("sunCloud")}Lisbon</h3>
      <div class="weather"><div class="now"><b>${icon("sunCloud")}</b><strong>18°</strong><span><small>Partly cloudy</small><i>H 20° L 14°</i></span></div>
      <ol><li>Today${icon("sunCloud")}<i>20° 14°</i></li><li>Sun${icon("sun")}<i>23° 15°</i></li>
      <li>Mon${icon("rain")}<i>19° 13°</i></li><li>Tue${icon("cloud")}<i>18° 12°</i></li></ol></div>`,
  },
  {
    key: "batteries", icon: "battery", name: "Batteries", line: "This Mac, your earbuds and their case, your keyboard.",
    html: `<h3>${icon("battery")}Batteries</h3>
      <div class="rings"><span class="ring charging" style="--level:71">${icon("laptop")}${icon("bolt")}</span>
      <span class="ring" style="--level:92">${icon("earbuds")}</span><span class="ring" style="--level:64">${icon("earbudsCase")}</span>
      <span class="ring" style="--level:38">${icon("keyboard")}</span></div>`,
  },
  {
    key: "focus", icon: "timer", name: "Focus", line: "Twenty-five minutes, one button. Try it.",
    html: `<h3>${icon("timer")}Focus</h3>
      <div class="focus"><strong data-clock>25:00</strong>
      <button type="button" data-focus aria-label="Start the focus timer">${icon("play")}</button>
      <span class="bar"><i data-bar></i></span></div>`,
  },
];
