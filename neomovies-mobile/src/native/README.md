# Native Extensions Plan (Expo + Kotlin/Swift + Rust)

This project is prepared for custom native features beyond JS runtime.

## Android

1. Create `modules/neomovies-core/android` as an Expo Module in Kotlin.
2. Add Rust static library (`cargo ndk`) for heavy parsing/crypto/media helpers.
3. Bind Kotlin <-> Rust via JNI in the module.
4. Expose methods to JS through Expo Modules API.

## iOS

1. Create `modules/neomovies-core/ios` as an Expo Module in Swift.
2. If Rust parity is required on iOS, use UniFFI/cbindgen or C-ABI bridge.
3. Expose methods to JS through Expo Modules API.

## Suggested first native use cases

- Secure token storage helpers around platform keystores.
- Fast media link parsing/normalization in Rust.
- Optional custom player bridge when JS stack is not enough.
