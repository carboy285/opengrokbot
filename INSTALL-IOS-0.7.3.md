# Install the updated iPhone interface · 0.7.3 (build 11)

1. Extract the new **OpenGrokBot-0.7.3-Source.zip** into a new folder.
2. Close the older Xcode project. Open **GrokBot.xcodeproj from this new folder**, rather than the previous project in Xcode's recent list.
3. Select the **GrokBot** scheme and your physical iPhone as the destination.
4. Use your existing signing team and the **same bundle identifier as the installed iPhone app**, so this replaces that copy instead of installing a second app with the same name.
5. Choose **Product → Run**. In the newly launched iPhone app, open **Settings** and confirm **App version: 0.7.3**. The earlier 0.6.1 release does not contain these changes.

The new home screen has round avatars, account initials, pinned Bot tiles at the top, arrowed conversation rows underneath, and floating search. Long-press a Bot and choose **Pin to top** or **Unpin Bot**. You can also change its pinned state in Bot details. Pinned tiles have no arrows and open their chats. The tap target is limited to the avatar/name tile, so empty space beside a single pinned Bot does not open it. Unpinned rows also open chats. Use the long-press menu or tap the chat title to open Bot details. The composer sits lower, without the host caption beneath it, and the full-width blur behind the top navigation controls has been removed. The attachment, send, and stop buttons match the Bot’s avatar color. Send and stop have full 48-point tap areas, and the composer background ignores taps so the controls receive them. Pins persist on this iPhone for each account and Mac.

The phone now remembers its Mac for a direct reconnect and requests updates sooner. To use the shorter polling waits on the Mac as well, run the **GrokBotMac** scheme from this project on your Mac. The published 0.6.1 DMG remains the older build.

No compilation, tests, or visual checks were run for this source update, as requested. Actual device appearance and connection speed have not been verified.

Desktop 0.7.3 also adds the encrypted account connection to Windows. Use Settings → Computer on either desktop to sign in and approve the iPhone. See docs/DESKTOP_0_7.md for the desktop changes and verification limits.

Update both your desktop app and iPhone app to 0.7.3 for shared pins. Pin changes sync through your account server. Chats now open at the latest message and follow replies until you scroll up. Swipe right from the left edge of a chat to return to your Bots. Scheduled tasks and cloud browser results run through the connected desktop.
