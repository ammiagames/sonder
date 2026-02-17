# Apple Sign-In: Post-License Checklist

Everything is implemented in code. Complete these steps after purchasing the Apple Developer Program license ($99/year).

## 1. Apple Developer Portal

- [ ] Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
- [ ] In **Certificates, Identifiers & Profiles > Identifiers**, select your App ID (`com.michaelsong.sonder`)
- [ ] Enable the **Sign in with Apple** capability and click **Edit**
  - Enable as a primary App ID
  - Check **Email Relay Service** if you want to relay emails to users who chose "Hide My Email"
- [ ] Register a **Services ID** (used by Supabase server-side verification)
  - Identifier: e.g. `com.michaelsong.sonder.auth`
  - Enable **Sign in with Apple**, then click **Configure**
  - Set the **Return URL** to your Supabase callback: `https://qxpkyblruhyrokexihef.supabase.co/auth/v1/callback`
- [ ] Create a **Key** with Sign in with Apple enabled
  - Download the `.p8` key file (you can only download it once)
  - Note the **Key ID** and your **Team ID**

## 2. Supabase Dashboard

- [ ] Go to **Authentication > Providers > Apple**
- [ ] Enable the Apple provider
- [ ] Enter the following values from step 1:
  - **Services ID** (the Services ID identifier, not the App ID)
  - **Secret Key** (contents of the `.p8` file)
  - **Key ID**
  - **Team ID**
- [ ] Save

## 3. Xcode

- [ ] Open the project in Xcode, select the **sonder** target
- [ ] Go to **Signing & Capabilities** and select your paid team (not "Personal Team")
- [ ] Verify the **Sign in with Apple** capability is present (already added in `sonder.entitlements`)
- [ ] Build and run on a real device or simulator

## 4. Test

- [ ] Tap "Sign in with Apple" on the auth screen
- [ ] Complete the Apple ID flow (choose to share or hide email)
- [ ] Verify the user is created in Supabase (`users` table)
- [ ] Sign out and sign back in — verify session restoration works
- [ ] Test the "Hide My Email" relay flow if email relay was configured

## 5. App Store Submission

- [ ] Apple **requires** Sign in with Apple if your app offers any other third-party sign-in (we have Google)
- [ ] Ensure the Sign in with Apple button follows [Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [ ] Test on multiple devices/OS versions before submitting
