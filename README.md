# CainerVision

CainerVision places 3D objects into the room in front of you, using the iPhone camera, then records a video where those objects look like they are really there. The buttons stay off the recording.

You can build it yourself with a free Apple ID. You do not need a paid Apple Developer account.

## What you need

- A Mac
- Xcode 15 or newer, free from the Mac App Store
- An iPhone that runs iOS 17 or newer (iPhone XR or later). A newer iPhone looks sharper.
- A cable to connect the iPhone to the Mac the first time
- The Apple ID you already use for the App Store

Object scanning and the most accurate occlusion need a Pro iPhone with a LiDAR scanner: iPhone 12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro, and later Pro models. Other iPhones still place objects, light them from the room, and record video.

## Get the project

1. On the Mac, open [github.com/cainering/CainerVision](https://github.com/cainering/CainerVision).
2. Click the green **Code** button.
3. Click **Download ZIP**.
4. Double-click the ZIP in Downloads so it unpacks into a folder named `CainerVision`.

If you already use Git:

```bash
git clone https://github.com/cainering/CainerVision.git
cd CainerVision
```

## Open it in Xcode

1. Open the unpacked folder.
2. Double-click **CainerVision.xcodeproj**. That blue icon opens Xcode.
3. Wait until the top progress bar finishes. The first open can take a minute.

If Xcode offers to update the project to the latest settings, click **Update**. That is safe.

The left sidebar is the project navigator. If you do not see it, choose **View → Navigators → Project** (or press ⌘1).

## Sign the app with your Apple ID

Signing is what tells the iPhone it is allowed to run an app you built. Your **team** is just your Apple ID. A **bundle identifier** is the app's unique name, written like a backwards web address. The one in this project is `com.cainering.CainerVision`. Only the Apple team that first registers that name can use it, so everyone else changes it to their own before the first Run.

1. In the Xcode menu bar, open **Xcode → Settings… → Accounts**.
2. Click the **+** at the bottom left, choose **Apple ID**, and sign in.
3. Close Settings.
4. In the project navigator, click the blue **CainerVision** project icon at the top.
5. In the main pane, under **TARGETS**, click **CainerVision**. (Click the target, the one with the app icon, if both a project and a target are listed.)
6. Open the **Signing & Capabilities** tab.
7. Check **Automatically manage signing**.
8. Open the **Team** menu and choose your name. It usually says **Personal Team** next to it.
9. If the Bundle Identifier field shows an error, or Xcode says the identifier is not available, change it. Click the text `com.cainering.CainerVision` and replace it with something only you use, such as `com.jane.CainerVision` or `com.jane.smith.CainerVision`. Use letters, numbers, and dots. Leave out spaces.

Stay online for this step. Xcode talks to Apple once to create a free signing certificate.

## Run it on your iPhone

The camera features need a real iPhone. The iOS Simulator on the Mac shows an explanation screen and does not track the room.

1. Plug the iPhone into the Mac. Unlock the phone.
2. If the phone asks you to **Trust This Computer**, tap Trust and enter the phone passcode.
3. At the top of the Xcode window, click the device menu next to the Run button. It may say "Any iOS Device" or the name of a simulator. Choose your iPhone from the list.
4. Press the **Run** button (the triangle), or choose **Product → Run**.
5. The first build takes a few minutes.

### If the iPhone says the developer is not trusted

1. On the iPhone, open **Settings → General → VPN & Device Management**.
2. Under Developer App, tap your Apple ID.
3. Tap **Trust**.
4. In Xcode, press Run again.

### If the iPhone asks for Developer Mode

Current iPhones require this before they will run an app from Xcode.

1. On the iPhone, open **Settings → Privacy & Security → Developer Mode**.
2. Turn Developer Mode on.
3. Restart the iPhone when it asks.
4. Unlock the phone and confirm that you want Developer Mode.
5. In Xcode, press Run again.

### Allow the camera

When CainerVision opens, tap **Continue**, then allow the camera. The microphone is asked for the first time you record with the mic button on. Photos is asked for the first time you save a clip.

A free Apple ID certificate lasts about 7 days. When the app stops opening, plug the phone back in and press Run again.

## How to use it

1. Move the phone slowly until a surface is found. A short coaching guide appears the first time.
2. The bottom tray holds sample objects: shapes, the word Hello, a warm cube, a cone, and a spinning token.
3. Tap an object in the tray. A ring appears on the floor or wall under the center of the screen.
4. Tap the surface to place the object. Tap again somewhere else to place another.
5. Tap an object to select it. Drag to move it, pinch to resize it, and rotate with two fingers.
6. The bar above the tray deletes, duplicates, or plays an animation when the model has one.
7. The red record button saves a video of the camera plus the 3D objects. The timer shows how long you have been recording. Tap the red square to stop. Clips stop automatically at 5 minutes.
8. The microphone button at the top includes sound. Turn it off for a silent clip.
9. After a clip is saved, it goes to Photos. The thumbnail at the lower left shares the latest clip.
10. The **+** button imports a USDZ, Reality, USD, or OBJ file, creates a shape or 3D text, or scans a real object on a LiDAR iPhone.

To import, export a USDZ from your 3D app when you can. OBJ files also work; they are scaled to about 20 cm so a model made in centimeters still fits on a table. A single-file `.usd`, `.usda`, or `.usdc` is packed into a USDZ as it is imported.

Scanning asks you to walk around the object. When the ring fills, flip the object or build the model. Building the model takes a few minutes and the phone should stay unlocked with CainerVision open. The scan uses the mobile detail level.

## Features

- Built-in shapes, 3D text, and sample USDZ models, including an animated token
- Import USDZ, Reality files, OBJ (with a simple color or texture from the MTL file), and single-file USD
- Create shapes and text with color, gloss, and metal
- On supported iPhones, scan a real object into a USDZ with Apple's Object Capture and on-device photogrammetry
- World tracking, horizontal and vertical planes, tap to place, drag, pinch, rotate, duplicate, and delete
- Several objects in one scene
- Playback of animations stored in a USDZ
- Room lighting and reflections, grounding shadows, people occlusion, and LiDAR mesh occlusion when the phone supports them
- Video recording of the composited camera and 3D view, without the on-screen buttons, at 30 fps with the short side at least 1080 pixels
- Optional microphone audio, save to Photos, and share

## Known limitations

- A real iPhone is required. The Simulator does not track the room.
- LiDAR mesh occlusion and object scanning are available on iPhone 12 Pro and later Pro models. Other iPhones still place, light, and record.
- On-device scans are Apple's reduced detail level. Reflective, transparent, and very thin objects scan poorly.
- Some animated USDZ files store motion in a form RealityKit does not play. When a model has a playable animation, a play button appears on the selection bar. The included Spinning Token uses a USD rotation so the marker on the coin turns.
- The recording is the AR view, scaled up on older phones so the short side is at least 1080 pixels. It is H.264 in an mp4, up to 5 minutes.
- The placed scene is kept only while the app is open. Starting a scan clears it, because the camera has to restart.
- A free Apple ID build expires after about 7 days until you Run it from Xcode again.

## If something goes wrong

**"Signing for CainerVision requires a development team."**
Open Signing & Capabilities and choose your Personal Team.

**The bundle identifier is already in use, or the profile could not be registered.**
Change the bundle identifier to one of your own, such as `com.yourname.CainerVision`, then press Run again.

**The Run button is gray.**
Choose your iPhone in the device menu at the top. The phone needs to be unlocked and trusted.

**"Unable to install" or the app flashes and closes.**
Trust the developer under Settings → General → VPN & Device Management, and turn on Developer Mode under Settings → Privacy & Security.

**Xcode says it does not support this iPhone.**
The iPhone's iOS version is newer than the Xcode you have. Update Xcode from the Mac App Store.

**The camera stays black.**
Use a physical iPhone, and allow the camera when iOS asks. If you previously tapped Don't Allow, open Settings → CainerVision → Camera.

**An imported model looks huge, tiny, or untextured.**
OBJ files are scaled to roughly 20 cm. USDZ files keep the size they were authored at, in meters. If a texture did not come along, put the image next to the OBJ and MTL and import the OBJ again.

## Ideas for later

- Export the camera path with the video so a desktop editor can re-composite the shot
- Match exposure and soften grounding shadows to the room
- Send a scan to a Mac for a higher-detail model
- Remember the scene between launches

## License

CainerVision is released under the MIT license. See [LICENSE](LICENSE).
