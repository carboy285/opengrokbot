# Install the updated iPhone interface · 0.6.6 (build 7)

1. Extract the new **OpenGrokBot-0.6.6-Xcode.zip** into a new folder.
2. Close the older Xcode project. Open **GrokBot.xcodeproj from this new folder**, rather than the previous project in Xcode's recent list.
3. Select the **GrokBot** scheme and your physical iPhone as the destination.
4. Use your existing signing team and the **same bundle identifier as the installed iPhone app**, so this replaces that copy instead of installing a second app with the same name.
5. Choose **Product → Run**. In the newly launched iPhone app, open **Settings** and confirm **App version: 0.6.6**. The earlier 0.6.1 release does not contain these changes.

The new home screen has round avatars, account initials, pinned Bot tiles at the top, arrowed conversation rows underneath, and floating search. Long-press a Bot and choose **Pin to top** or **Unpin Bot**. You can also change its pinned state in Bot details. Pinned tiles have no arrows and open their chats. The tap target is limited to the avatar/name tile, so empty space beside a single pinned Bot does not open it. Unpinned rows also open chats. Use the long-press menu or tap the chat title to open Bot details. The composer sits lower, without the host caption beneath it, and the full-width blur behind the top navigation controls has been removed. The attachment, send, and stop buttons match the Bot’s avatar color. Send and stop have full 48-point tap areas, and the composer background ignores taps so the controls receive them. Pins persist on this iPhone for each account and Mac.

The phone now remembers its Mac for a direct reconnect and requests updates sooner. To use the shorter polling waits on the Mac as well, run the **GrokBotMac** scheme from this project on your Mac. The published 0.6.1 DMG remains the older build.

No compilation, tests, or visual checks were run for this source update, as requested. Actual device appearance and connection speed have not been verified.
