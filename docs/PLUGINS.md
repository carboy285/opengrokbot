# Plugins (Windows and browser versions)

A plugin gives your Bots extra actions: look something up in your own system, run a script, call an API you use. It is a folder of your own code, so **a plugin can do anything this app can do**. Only add plugins you wrote or have read.

## Turn one on

Plugins are off. A plugin loads only if its name is listed in `settings.json` (in the app's data folder, `%APPDATA%\OpenGrokBot` on Windows, or `OPENGROKBOT_DATA_DIR` in Docker):

```json
{ "plugins": { "allowed": ["weather"] } }
```

In Docker, set `OPENGROKBOT_PLUGINS=weather` instead. Restart the app after changing it.

## Write one

Make `plugins/weather/` inside the data folder with two files.

`plugin.json`:

```json
{
  "name": "weather",
  "version": "1.0",
  "description": "Weather forecasts",
  "actions": [
    { "name": "forecast", "description": "Forecast for a city. Input: {\"city\": \"Oslo\"}" },
    { "name": "radar_link", "description": "A link to the radar map", "approval": false }
  ]
}
```

`index.cjs`:

```js
module.exports = {
  async run(action, args, context) {   // context: { botID, botName }
    if (action === 'forecast') return `Sunny in ${args.city}`;
    if (action === 'radar_link') return 'https://example.com/radar';
  }
};
```

Rules:

- The folder name must equal `name`: lowercase letters, numbers and hyphens, 2 to 40 characters.
- Up to 20 actions; action names use lowercase letters, numbers and underscores.
- Each action **asks you before it runs** unless its manifest sets `"approval": false`. Unattended routines skip actions that ask.
- A run stops after 30 seconds. Results are cut at 12,000 characters and shown to the Bot as untrusted text, never as instructions or approval.
- A plugin that is broken, misnamed or not exporting `run()` is skipped; the app keeps working.

Bots learn about allowed plugins automatically and call them with `{"action":"plugin","plugin":"weather","name":"forecast","arguments":{"city":"Oslo"}}`.

Mac and iPhone do not run plugins yet.
