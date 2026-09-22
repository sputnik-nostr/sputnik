# NIPs

A list of Nostr NIPs, detailing which ones we plan to implement (or not).

| NIP  | Description                                          | Status                                      |
| :--- | :--------------------------------------------------- | :------------------------------------------ |
| `01` | Basic protocol flow description                      | Implemented (read + post)                   |
| `02` | Follow List                                          | Implemented (read + write)                  |
| `05` | Mapping Nostr keys to DNS-based internet identifiers | Implemented (verification)                  |
| `09` | Event Deletion Request                               | Implemented (own reactions/reposts only)    |
| `10` | Text Notes and Threads                               | Implemented (read + reply)                  |
| `18` | Reposts                                              | Implemented (repost only, quotes read-only) |
| `19` | bech32-encoded entities                              | Partial (no `naddr`)                        |
| `21` | `nostr:` URI scheme                                  | Partial (no `naddr`)                        |
| `25` | Reactions                                            | Implemented (read + write)                  |
| `27` | Text Note References                                 | Implemented (read only)                     |
| `65` | Relay List Metadata                                  | Partial (no outbox routing)                 |
| `92` | Media Attachments Metadata (`imeta`)                 | Partial (read only)                         |
| `A3` | payto: Payment Targets                               | Implemented (read + write)                  |
| `B7` | Blossom                                              | Partial (read only)                         |

## Longer-term:

| NIP  | Description                         | Status          |
| :--- | :---------------------------------- | :-------------- |
| `11` | Relay Information Document          | Support planned |
| `14` | Subject tag in Text events          | Support planned |
| `23` | Long-form Content                   | Considering     |
| `36` | Sensitive Content / Content Warning | Support planned |

## Not planned

- Mapping/activity tracking
- Chatrooms, forums, and groups
- Git and torrents
- Badges and highlights
- "Data Vending Machines"
- Classified listings
- Short-form video content
- Anything related to the Lightning Network
- Legacy DMs
