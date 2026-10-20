# Midnight Geprek — Task Roadmap

Legenda: [ ] Not Started · [~] In Progress · [R] Ready for Review · [x] Verified by User
Aturan: satu sub-phase per patch. Lihat PROJECT_INSTRUCTIONS.md dan CONCEPT.md.

## Phase 0 — Repository Audit & Project Contract
- [ ] 0.1 Audit repository
- [ ] 0.2 docs/GDD_TRACEABILITY.md
- [ ] 0.3 Development commands

## Phase 1 — Rojo Foundation & Bootstrapping
- [ ] 1.1 Rojo mapping
- [ ] 1.2 Bootstrap & config dasar
- [ ] 1.3 Shared types & remote contract
- [ ] 1.4 Test harness / debug flags (dev-only)

## Phase 2 — Session, Game Modes & Day/Time
- [ ] 2.1 Game session state (run vs unlock permanen)
- [ ] 2.2 Story Mode (hari 1–7)
- [ ] 2.3 Free Mode
- [ ] 2.4 Day phase: Preparation → Business Hours → Late Night → Closing
- [ ] 2.5 Hari 7 & transisi ke evaluasi ending

## Phase 3 — OrderSystem
- [ ] 3.1 Order data model & lifecycle
- [ ] 3.2 Order remotes & validation
- [ ] 3.3 Order creation & customer integration
- [ ] 3.4 Order UI & interaction feedback
- [ ] 3.5 Serve/Refuse resolution
- [ ] 3.6 Timeout, closing & cleanup
- [ ] 3.7 OrderSystem tests & integration gate

## Phase 4 — Cooking & Serving
- [ ] 4.1 Recipe config
- [ ] 4.2 Cooking lifecycle
- [ ] 4.3 Serve handoff
- [ ] 4.4 Quality & mistake handling

## Phase 5 — Economy & Reputation
- [ ] 5.1 EconomyService
- [ ] 5.2 Price/reward/expense config
- [ ] 5.3 ReputationService (0–100)
- [ ] 5.4 Bangkrut fail state
- [ ] 5.5 Balance simulation (Rp5.000.000 / 7 hari)

## Phase 6 — Customer AI, Anomaly & Punishment
- [ ] 6.1 Customer state machine (Spawn → Approach → Order → Wait → Serve/Refuse → Leave)
- [ ] 6.2 Customer profiles/config (Normal, Suspicious, Anomaly, Mystery, Secret)
- [ ] 6.3 Anomaly rules framework
- [ ] 6.4 First anomaly end-to-end
- [ ] 6.5 Nusantara anomaly pack (Kuntilanak, Pocong, Genderuwo, Jenglot)
- [ ] 6.6 Level 999999 special customer (Secret Ending)
- [ ] 6.7 PunishmentService + config tier punishment
- [ ] 6.8 Jumpscare framework (server trigger, client play, cooldown, Off/Reduced/Full, tanpa strobo)

## Phase 7 — Quest & Investigation
- [ ] 7.1 Quest framework
- [ ] 7.2 Warisan Ayah
- [ ] 7.3 Rumor Warga
- [ ] 7.4 Ruko Sebelah
- [ ] 7.5 Target 5 Juta
- [ ] 7.6 Jimat Ayah
- [ ] 7.7 Quest UI & hints

## Phase 8 — Items & Persistence
- [ ] 8.1 Item definitions
- [ ] 8.2 Item interactions
- [ ] 8.3 Save schema (versioned)
- [ ] 8.4 Load/save safety
- [ ] 8.5 Persistence tests

## Phase 9 — Ending Manager & Narrative
- [ ] 9.1 Central EndingService
- [ ] 9.2 Happy Ending
- [ ] 9.3 Bad Ending
- [ ] 9.4 True Ending
- [ ] 9.5 Secret Ending
- [ ] 9.6 Bangkrut Ending
- [ ] 9.7 Ending priority & regression

## Phase 10 — Map & World Integration
- [ ] 10.1 Map interaction contract (tag/attribute)
- [ ] 10.2 Main shop & kitchen
- [ ] 10.3 Customer waiting area & front road
- [ ] 10.4 Neighbor shop investigation
- [ ] 10.5 Villager area & father's grave
- [ ] 10.6 Lighting & performance pass

## Phase 11 — UI/UX & Accessibility
- [ ] 11.1 HUD
- [ ] 11.2 Interaction prompt (PC/mobile/controller)
- [ ] 11.3 Order/cooking UI
- [ ] 11.4 Anomaly feedback & tutorial
- [ ] 11.5 Subtitle & audio settings (+ intensitas jumpscare)
- [ ] 11.6 Accessibility QA

## Phase 12 — Audio, VFX & Atmosphere
- [ ] 12.1 Audio event map
- [ ] 12.2 Audio settings integration
- [ ] 12.3 VFX pass
- [ ] 12.4 Audio/VFX performance

## Phase 13 — Integration & Vertical Slice
- [ ] 13.1 One complete day
- [ ] 13.2 Core gameplay loop
- [ ] 13.3 One anomaly end-to-end (termasuk punishment)
- [ ] 13.4 One ending end-to-end
- [ ] 13.5 Vertical slice gate

## Phase 14 — Content Production
- [ ] 14.1 Customer variety
- [ ] 14.2 Anomaly content pack
- [ ] 14.3 Quest narrative content
- [ ] 14.4 Cutscenes
- [ ] 14.5 Polish map content

## Phase 15 — QA, Balancing & Security
- [ ] 15.1 Functional regression
- [ ] 15.2 Exploit/remote validation
- [ ] 15.3 Ending matrix
- [ ] 15.4 Economy balancing
- [ ] 15.5 Anomaly readability
- [ ] 15.6 Performance & mobile
- [ ] 15.7 Save data QA

## Phase 16 — Release Candidate
- [ ] 16.1 Build & project hygiene
- [ ] 16.2 Release checklist
- [ ] 16.3 Submission/publication prep
