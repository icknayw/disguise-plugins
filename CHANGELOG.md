# Changelog

## 1.1.0

- Projector Monitor: Epson support (ESC/VP21 over the HTTP control API with Digest authentication) for power, shutter, input, signal, fault, freeze, serial and light-source hours. Choose the brand per projector; existing configurations load as Panasonic.
- Projector Monitor: protocol code split into per-brand drivers; slot state is passed directly instead of being swapped through script globals; remembered control request IDs are capped; blank IPs are validated without a placeholder address; the readings dialog hides values a brand does not report; window-fit replies are returned as JSON.

## 1.0.0

- Device Monitor: configurable devices, concurrent ping checks, compact cards and shared size widths.
- Projector Monitor: up to 12 projectors, saved credentials, power/shutter controls, readings and configurable layouts.
- World Clock: up to 8 saved timezones, three sizes, minute precision and NRMW branding.
- Videohub Monitor: saved endpoint, visible-port filters, automatic sizing, transposed orientation, batch Take, click-to-unselect and confirmed routing feedback.
- Portable local defaults, individual install guides, and configurable shared hosting without show-specific addresses.
