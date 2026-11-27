# Install CainerVision on your iPhone

GitHub builds the app and sends it to Apple. You install it with the TestFlight app.

Use the Apple ID **cainering@gmail.com**. That is the Apple Developer account. The build uses the App Store Connect API key already stored in GitHub. It never asks for the Apple password.

## Once: create the app in App Store Connect

Apple does not let the API key create the app record. The bundle id `com.cainering.CainerVision` is already registered. You create the app record once, in the browser.

1. On a computer, sign in to [App Store Connect](https://appstoreconnect.apple.com) as **cainering@gmail.com**.
2. If Apple shows an agreement, open [Agreements, Tax, and Banking](https://appstoreconnect.apple.com/agreements) and accept it. Accept the Paid Applications agreement too. CainerVision is free, and Apple still requires that agreement.
3. Click **Apps**.
4. Click the **+** button, then **New App**.
5. Fill in the form:
   - Platforms: **iOS**
   - Name: **CainerVision**
   - Primary language: **English (U.S.)**
   - Bundle ID: **com.cainering.CainerVision**
   - SKU: **cainervision-ios**
   - User Access: **Full Access**
6. Click **Create**.

## 1. Start a build

1. Open the [TestFlight workflow](https://github.com/cainering/CainerVision/actions/workflows/testflight.yml).
2. Click **Run workflow**.
3. Leave the branch set to **main**.
4. Click the green **Run workflow** button.
5. Wait until the yellow dot turns green. The first build often takes about 30 minutes.

A push to the `main` branch starts the same build. The green run page shows the build number that was uploaded.

## 2. Install it on the iPhone

1. Wait for Apple to finish processing. This usually takes 10 to 30 minutes after the workflow is green. Apple emails **cainering@gmail.com** when the build is ready.
2. On the iPhone, install **TestFlight** from the App Store.
3. Sign the iPhone in with **cainering@gmail.com**.
4. Open TestFlight, tap **CainerVision**, then tap **Install**.

## If TestFlight does not show the app

On a computer, sign in to [App Store Connect](https://appstoreconnect.apple.com) as **cainering@gmail.com**.

1. If Apple shows an agreement, open [Agreements, Tax, and Banking](https://appstoreconnect.apple.com/agreements) and accept it. Accept the Paid Applications agreement too. CainerVision is free, and Apple still requires that agreement. Then run the workflow again.
2. If the Apple Developer site asks you to review the license, open [developer.apple.com/account](https://developer.apple.com/account) and accept it. Then run the workflow again.
3. Open **Apps**, then **CainerVision**, then **TestFlight**, then **Internal Testing**.
4. Open the **App Store Connect Users** group.
5. If the latest build is missing, click the **+** next to Builds, select that build, and click **Add**. Turn on automatic distribution if Apple offers it.
6. Confirm **cainering@gmail.com** is listed as a tester.
7. On the iPhone, open TestFlight again and tap **Install**.

## If Apple asks about encryption

Choose **No**. CainerVision does not use non-exempt encryption.
