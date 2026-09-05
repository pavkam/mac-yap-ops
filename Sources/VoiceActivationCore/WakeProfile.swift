// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// The semantic accent applied to a profile's menu and recording presentation.
public enum WakeProfileAccent: String, CaseIterable, Codable, Equatable, Sendable {
    /// A cyan accent.
    case cyan
    /// A blue accent.
    case blue
    /// A purple accent.
    case purple
    /// A pink accent.
    case pink
    /// An orange accent.
    case orange
    /// A green accent.
    case green
}

/// A wake phrase, its invocation action, and its independent listening controls.
public struct WakeProfile: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case wakePhrase
        case action
        case executablePath
        case argumentTemplates
        case accent
        case isEnabled
        case pushToTalkHotKey
        case speechPreference
    }

    /// Errors that make a wake profile impossible to activate safely.
    public enum ValidationError: Error, Equatable, LocalizedError {
        /// The normalized wake phrase contains no spoken characters.
        case wakePhraseRequired
        /// The normalized display name is empty.
        case nameRequired
        /// The normalized display name exceeds its persisted bound.
        case nameTooLong
        /// The icon payload cannot be rendered safely.
        case invalidIcon
        /// A direct command has no transcript placeholder in its arguments.
        case missingTranscriptPlaceholder
        /// A caller requested command-only compatibility data from an agent profile.
        case actionIsNotCommand

        /// A user-presentable explanation of the invalid profile.
        public var errorDescription: String? {
            switch self {
            case .wakePhraseRequired:
                "Every wake profile needs a wake phrase."
            case .nameRequired:
                "Every profile needs a name."
            case .nameTooLong:
                "Profile names cannot exceed 80 characters."
            case .invalidIcon:
                "Choose one emoji or a valid SF Symbol name."
            case .missingTranscriptPlaceholder:
                "Every wake profile URL must contain {text} or {urlText}."
            case .actionIsNotCommand:
                "This wake profile does not run a direct command."
            }
        }
    }

    /// The stable initial profile used for first launch and corrupt-data recovery.
    public static let defaultValue = try! WakeProfile(
        id: UUID(uuidString: "50443ED5-4EBC-40CA-8434-AFBCA06BEE5A")!,
        name: "Computer",
        wakePhrase: "computer",
        executablePath: "/usr/bin/open",
        argumentTemplates: ["https://www.google.com/search?q={urlText}"],
        accent: .blue)

    /// The stable identity used for shortcut registration and cached agent sessions.
    public let id: UUID
    /// The normalized user-facing identity of the profile.
    public var name: String
    /// The portable symbol or emoji rendered with the profile.
    public var icon: ProfileIcon
    /// The normalized phrase that begins capture for this profile.
    public var wakePhrase: String
    /// The direct command or agent harness invoked by this profile.
    public var action: WakeProfileAction
    /// The semantic color applied to this profile's presentation.
    public var accent: WakeProfileAccent
    /// Whether passive recognition listens for this profile's phrase.
    public var isEnabled: Bool
    /// The optional global shortcut that captures directly for this profile.
    public var pushToTalkHotKey: PushToTalkHotKey?
    /// The profile's explicit, disabled, or inherited speech behavior.
    public var speechPreference: ProfileSpeechPreference

    /// The direct-command executable path, or an empty string for agent profiles.
    public var executablePath: String {
        guard case let .command(template) = action else { return "" }
        return template.executablePath
    }

    /// The direct-command argument templates, or an empty list for agent profiles.
    public var argumentTemplates: [String] {
        guard case let .command(template) = action else { return [] }
        return template.argumentTemplates
    }

    /// Creates a profile around an already validated action.
    ///
    /// - Parameters:
    ///   - id: The stable profile identity.
    ///   - wakePhrase: The phrase that begins capture.
    ///   - action: The operation invoked with captured text.
    ///   - accent: The semantic presentation accent.
    ///   - isEnabled: Whether passive listening includes this profile.
    ///   - pushToTalkHotKey: An optional profile-specific global shortcut.
    /// - Throws: ``ValidationError/wakePhraseRequired`` for an empty spoken phrase.
    public init(
        id: UUID = UUID(),
        name: String? = nil,
        icon: ProfileIcon = .defaultValue,
        wakePhrase: String,
        action: WakeProfileAction,
        accent: WakeProfileAccent,
        isEnabled: Bool = true,
        pushToTalkHotKey: PushToTalkHotKey? = nil,
        speechPreference: ProfileSpeechPreference = .inherit) throws
    {
        let normalizedPhrase = WakePhraseMatcher.normalizedWakePhrase(wakePhrase)
        guard WakePhraseMatcher.containsSpokenCharacter(normalizedPhrase) else {
            throw ValidationError.wakePhraseRequired
        }
        let normalizedName = Self.normalizedName(name ?? Self.derivedName(from: normalizedPhrase))
        guard !normalizedName.isEmpty else {
            throw ValidationError.nameRequired
        }
        guard normalizedName.count <= 80 else {
            throw ValidationError.nameTooLong
        }
        guard icon.isValid else {
            throw ValidationError.invalidIcon
        }

        self.id = id
        self.name = normalizedName
        self.icon = icon
        self.wakePhrase = normalizedPhrase
        self.action = action
        self.accent = accent
        self.isEnabled = isEnabled
        self.pushToTalkHotKey = pushToTalkHotKey
        self.speechPreference = speechPreference
    }

    /// Creates a profile that opens one transcript-expanded URL.
    ///
    /// - Parameters:
    ///   - id: The stable profile identity.
    ///   - wakePhrase: The phrase that begins capture.
    ///   - urlTemplate: A URL containing `{text}` or `{urlText}`.
    ///   - accent: The semantic presentation accent.
    ///   - isEnabled: Whether passive listening includes this profile.
    ///   - pushToTalkHotKey: An optional profile-specific global shortcut.
    /// - Throws: A profile or command-template validation error.
    public init(
        id: UUID = UUID(),
        name: String? = nil,
        icon: ProfileIcon = .defaultValue,
        wakePhrase: String,
        urlTemplate: String,
        accent: WakeProfileAccent,
        isEnabled: Bool = true,
        pushToTalkHotKey: PushToTalkHotKey? = nil,
        speechPreference: ProfileSpeechPreference = .inherit) throws
    {
        try self.init(
            id: id,
            name: name,
            icon: icon,
            wakePhrase: wakePhrase,
            executablePath: "/usr/bin/open",
            argumentTemplates: [urlTemplate],
            accent: accent,
            isEnabled: isEnabled,
            pushToTalkHotKey: pushToTalkHotKey,
            speechPreference: speechPreference)
    }

    /// Creates a profile that runs a transcript-expanded direct process.
    ///
    /// - Parameters:
    ///   - id: The stable profile identity.
    ///   - wakePhrase: The phrase that begins capture.
    ///   - executablePath: The absolute executable path.
    ///   - argumentTemplates: Arguments containing a transcript placeholder.
    ///   - accent: The semantic presentation accent.
    ///   - isEnabled: Whether passive listening includes this profile.
    ///   - pushToTalkHotKey: An optional profile-specific global shortcut.
    /// - Throws: A profile or command-template validation error.
    public init(
        id: UUID = UUID(),
        name: String? = nil,
        icon: ProfileIcon = .defaultValue,
        wakePhrase: String,
        executablePath: String,
        argumentTemplates: [String],
        accent: WakeProfileAccent,
        isEnabled: Bool = true,
        pushToTalkHotKey: PushToTalkHotKey? = nil,
        speechPreference: ProfileSpeechPreference = .inherit) throws
    {
        guard argumentTemplates.contains(where: {
            $0.contains("{text}") || $0.contains("{urlText}")
        }) else {
            throw ValidationError.missingTranscriptPlaceholder
        }
        let commandTemplate = try CommandTemplate(
            executablePath: executablePath,
            argumentTemplates: argumentTemplates)
        try self.init(
            id: id,
            name: name,
            icon: icon,
            wakePhrase: wakePhrase,
            action: .command(commandTemplate),
            accent: accent,
            isEnabled: isEnabled,
            pushToTalkHotKey: pushToTalkHotKey,
            speechPreference: speechPreference)
    }

    /// Decodes current profiles and migrates the legacy command-only shape.
    ///
    /// - Parameter decoder: The persisted profile decoder.
    /// - Throws: A decoding or profile validation error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action: WakeProfileAction
        if container.contains(.action) {
            action = try container.decode(WakeProfileAction.self, forKey: .action)
        } else {
            action = .command(try CommandTemplate(
                executablePath: container.decode(String.self, forKey: .executablePath),
                argumentTemplates: container.decode([String].self, forKey: .argumentTemplates)))
        }
        let wakePhrase = try container.decode(String.self, forKey: .wakePhrase)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decodeIfPresent(String.self, forKey: .name),
            icon: container.decodeIfPresent(ProfileIcon.self, forKey: .icon) ?? .defaultValue,
            wakePhrase: wakePhrase,
            action: action,
            accent: container.decode(WakeProfileAccent.self, forKey: .accent),
            isEnabled: container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            pushToTalkHotKey: container.decodeIfPresent(
                PushToTalkHotKey.self,
                forKey: .pushToTalkHotKey),
            speechPreference: container.decodeIfPresent(
                ProfileSpeechPreference.self,
                forKey: .speechPreference) ?? .inherit)
    }

    /// Encodes the current action-based profile representation.
    ///
    /// - Parameter encoder: The destination encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(wakePhrase, forKey: .wakePhrase)
        try container.encode(action, forKey: .action)
        try container.encode(accent, forKey: .accent)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(pushToTalkHotKey, forKey: .pushToTalkHotKey)
        try container.encode(speechPreference, forKey: .speechPreference)
    }

    /// The direct-command template represented by this profile.
    ///
    /// - Throws: ``ValidationError/actionIsNotCommand`` for agent profiles.
    public var commandTemplate: CommandTemplate {
        get throws {
            guard case let .command(template) = action else {
                throw ValidationError.actionIsNotCommand
            }
            return template
        }
    }

    private static func normalizedName(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func derivedName(from wakePhrase: String) -> String {
        wakePhrase.capitalized
    }
}
