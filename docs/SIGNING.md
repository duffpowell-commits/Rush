# Signing: one key for every game

Android only installs an update over an app signed with the same key. So every game Duff makes
is signed with ONE key: `signing/games.keystore.enc` (the same file Lethemoor uses), committed
encrypted. CI unlocks it with the repo secret **LM_KEYSTORE_PASS** (Duff has the passphrase).
Different games keep different package names (`com.duffpowell.<repo>`), so they install side by side.

## Each new game repo needs the secret (GitHub doesn't copy secrets from a template)
On the phone, in the GitHub site (not the app):
1. Open the repo -> Settings -> Secrets and variables -> Actions -> New repository secret.
2. Name: `LM_KEYSTORE_PASS`. Value: the passphrase. Add secret.
3. Actions -> build -> Run workflow (or push anything) to make a signed build.
Without it, CI still builds but warns: that APK can't update an installed copy.

## Never
- Never commit the unlocked keystore or the passphrase. Never generate a new key for a game:
  lose the key and installed copies can never update again.
- The key details: alias `androiddebugkey`, store/key password `android` (the passphrase is the
  real lock).
