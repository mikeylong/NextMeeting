import SwiftUI
import AppKit

private enum PanelStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.40, green: 0.69, blue: 1, alpha: 1)
            : NSColor(red: 0.0, green: 0.42, blue: 0.88, alpha: 1)
    })
    static let card = Color.primary.opacity(0.045)
    static let rule = Color.primary.opacity(0.08)
}

struct MeetingPanel: View {
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var navigation: PanelNavigation
    private var showingSettings: Bool {
        get { navigation.showingSettings }
        nonmutating set { navigation.showingSettings = newValue }
    }
    private var selectedMeeting: Meeting? {
        get { navigation.selectedMeeting }
        nonmutating set {
            navigation.selectedMeeting = newValue
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header
                Rectangle().fill(PanelStyle.rule).frame(height: 1)
                if showingSettings {
                    settings
                } else if let meeting = selectedMeeting {
                    meetingDetail(meeting, now: context.date)
                } else if store.access != .granted {
                    connection
                } else {
                    agenda(now: context.date)
                }
                footer(now: context.date)
            }
            .frame(width: 340, height: PanelLayout.height(meetingCount: store.meetings.count, access: store.access,
                                                       showingSettings: showingSettings, showingDetails: selectedMeeting != nil))
            // NSPopover supplies one native surface for the body and its arrow.
            .tint(PanelStyle.accent)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ||
                                  Bundle.main.object(forInfoDictionaryKey: "NextMeetingPreviewAppearance") as? String == "light" ? .light : nil)
            .onChange(of: store.access) { _, access in
                if access != .granted { selectedMeeting = nil }
            }
            .onChange(of: store.meetings) { _, meetings in
                if let selected = selectedMeeting {
                    selectedMeeting = meetings.first { $0.id == selected.id }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            if showingSettings || selectedMeeting != nil {
                Button {
                    showingSettings = false
                    selectedMeeting = nil
                } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(IconButtonStyle()).help("Back to meetings")
                    .accessibilityLabel("Back to meetings")
            }
            Text(showingSettings ? "Settings" : selectedMeeting != nil ? "Meeting" : "Next Meeting")
                .font(.system(size: 14, weight: .semibold))
            if store.isDemo {
                Text("PREVIEW").font(.system(size: 8, weight: .bold)).tracking(0.7)
                    .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(PanelStyle.card, in: Capsule())
            }
            Spacer()
            if !showingSettings {
                Button { showingSettings = true; selectedMeeting = nil } label: {
                    Image(systemName: "gearshape").font(.system(size: 14))
                }.buttonStyle(IconButtonStyle()).help("Settings").accessibilityLabel("Settings")
            }
            Menu {
                Button("Refresh Calendars", systemImage: "arrow.clockwise") { store.refresh() }
                    .keyboardShortcut("r")
                Button("Open Calendar", systemImage: "calendar") { openCalendarSelection() }
                Divider()
                Button("Quit Next Meeting") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 24, height: 26).help("More options").accessibilityLabel("More options")
        }
        .padding(.horizontal, 16).frame(height: 45)
    }

    private func agenda(now: Date) -> some View {
        let meetings = MeetingLogic.upcoming(store.meetings, now: now)
        let next = MeetingLogic.nextMeeting(meetings, now: now)
        return VStack(spacing: 0) {
            if let next {
                featuredMeeting(next, now: now).padding(.horizontal, 16).padding(.vertical, 17)
                Rectangle().fill(PanelStyle.rule).frame(height: 1).padding(.horizontal, 16)
            } else {
                emptyAgenda.padding(.horizontal, 24).frame(height: 150)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Next 24 hours").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(meetings.count) \(meetings.count == 1 ? "meeting" : "meetings")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 7)

            if meetings.isEmpty {
                VStack(spacing: 12) {
                    Rectangle().fill(PanelStyle.rule).frame(height: 1)
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle").foregroundStyle(PanelStyle.accent)
                        Text(store.calendars.isEmpty ? "Add an account to Apple Calendar." :
                            store.calendars.allSatisfy { !store.isCalendarEnabled($0.id) }
                            ? "Choose a calendar in Settings." : "Your schedule is clear.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }.font(.system(size: 12))
                    Button(store.calendars.isEmpty ? "Add calendar account" : "Choose calendars") {
                        if store.calendars.isEmpty { AppActions.openCalendarAccounts() }
                        else { showingSettings = true }
                    }.buttonStyle(QuietButtonStyle())
                }.padding(.horizontal, 22)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped(meetings), id: \.date) { group in
                            Section {
                                ForEach(group.meetings) { meeting in
                                    MeetingRow(meeting: meeting, now: now) { selectedMeeting = meeting }
                                    if meeting.id != group.meetings.last?.id {
                                        Rectangle().fill(PanelStyle.rule).frame(height: 1).padding(.leading, 70)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(dayLabel(group.date, now: now)).font(.system(size: 10, weight: .semibold))
                                        .tracking(0.6).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(group.date.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                            }
                        }
                    }.padding(.bottom, 8)
                }.scrollIndicators(.automatic)
            }
            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 22).padding(.vertical, 7)
            }
        }.frame(maxHeight: .infinity)
    }

    private func featuredMeeting(_ meeting: Meeting, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(countdownNumber(meeting, now: now))
                    .font(.system(size: 30, weight: .regular)).monospacedDigit()
                Text(countdownUnit(meeting, now: now))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.bottom, 7)

            Button { selectedMeeting = meeting } label: {
                Text(meeting.title).font(.system(size: 17, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).help("Show meeting details")

            HStack(spacing: 5) {
                Circle().fill(Color(hex: meeting.colorHex)).frame(width: 5, height: 5)
                Text(meeting.calendarTitle).lineLimit(1)
                Text("·")
                Text(timeRange(meeting)).monospacedDigit().lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)

            if let url = meeting.joinURL {
                Button { if !store.isDemo { NSWorkspace.shared.open(url) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "video")
                        Text("Join meeting")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                }.buttonStyle(JoinButtonStyle()).padding(.top, 15)
                    .help(store.isDemo ? "Joining is disabled in preview" : "Open meeting link")
                    .disabled(store.isDemo)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: meeting.location == nil ? "calendar" : "mappin")
                    Text(meeting.location ?? "No meeting link").lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyAgenda: some View {
        let noSelection = !store.calendars.isEmpty && store.calendars.allSatisfy { !store.isCalendarEnabled($0.id) }
        return VStack(spacing: 11) {
            Image(systemName: noSelection || store.calendars.isEmpty ? "calendar" : "calendar.badge.checkmark")
                .font(.system(size: 27, weight: .light)).foregroundStyle(.secondary).frame(height: 36)
            Text(noSelection ? "No calendars selected" : store.calendars.isEmpty ? "Add your calendars" : "No meetings ahead")
                .font(.system(size: 20, weight: .medium))
            Text(noSelection ? "Choose the calendars you want to see." : store.calendars.isEmpty
                 ? "Connect an account to Apple Calendar." : "Your next 24 hours are clear.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36, weight: .light)).foregroundStyle(PanelStyle.accent)
                .frame(width: 80, height: 80)
                .background(PanelStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 23))
                .padding(.bottom, 25)
            Text(store.access == .notDetermined ? "Your next meeting.\nA glance away." : "Allow calendar access")
                .font(.system(size: 27, weight: .medium)).lineSpacing(2).padding(.bottom, 12)
            Text(store.access == .notDetermined
                 ? "See what’s next and the meetings ahead, right from your menu bar."
                 : "Next Meeting needs permission to show events from your calendars.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            VStack(alignment: .leading, spacing: 12) {
                Label("Uses the accounts in Apple Calendar", systemImage: "calendar")
                Label("Updates when your calendars change", systemImage: "arrow.triangle.2.circlepath")
                Label("Your events stay on this Mac", systemImage: "lock")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 24)

            Button {
                if store.access == .notDetermined || store.access == .writeOnly { store.requestAccess() }
                else { AppActions.openPrivacySettings() }
            } label: {
                HStack {
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                    Text(store.access == .notDetermined || store.access == .writeOnly ? "Connect calendars" : "Open System Settings")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }.buttonStyle(JoinButtonStyle()).disabled(store.isRefreshing)
            if store.access == .notDetermined {
                Text("macOS will ask for calendar access.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 10)
            } else {
                Text("Privacy & Security → Calendars → Next Meeting")
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10)
            }
            if let error = store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 10)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendars").font(.system(size: 17, weight: .semibold))
                    Text("Choose which calendars appear in Next Meeting.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }
                if store.access != .granted {
                    Button("Connect calendars") {
                        showingSettings = false
                    }.buttonStyle(QuietButtonStyle())
                } else if store.calendars.isEmpty {
                    Text("No calendars found. Add an account to Apple Calendar to get started.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(calendarSources, id: \.self) { source in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(source.uppercased()).font(.system(size: 9, weight: .semibold))
                                .tracking(0.6).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                ForEach(store.calendars.filter { $0.source == source }) { calendar in
                                    Toggle(isOn: Binding(get: { store.isCalendarEnabled(calendar.id) },
                                                         set: { store.setCalendar(id: calendar.id, enabled: $0) })) {
                                        HStack(spacing: 8) {
                                            Circle().fill(Color(hex: calendar.colorHex)).frame(width: 7, height: 7)
                                            Text(calendar.title).font(.system(size: 12)).lineLimit(2)
                                        }
                                    }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    if calendar.id != store.calendars.filter({ $0.source == source }).last?.id {
                                        Divider().padding(.horizontal, 12)
                                    }
                                }
                            }.background(PanelStyle.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                Button { AppActions.openCalendarAccounts() } label: {
                    HStack {
                        Text("Manage calendar accounts")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }
                }.buttonStyle(QuietButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Preferences").font(.system(size: 15, weight: .semibold))
                    VStack(spacing: 0) {
                        Toggle("Show meeting title in menu bar", isOn: $preferences.showMeetingTitle)
                            .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).padding(12)
                        Divider().padding(.horizontal, 12)
                        Toggle("Open at login", isOn: Binding(get: { preferences.launchesAtLogin },
                                                             set: { preferences.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).padding(12)
                            .disabled(store.isDemo)
                    }.background(PanelStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    if let error = preferences.loginError {
                        Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Private by default", systemImage: "lock").font(.system(size: 11, weight: .medium))
                    Text("Next Meeting reads your calendars on this Mac. It never changes events or sends them to a server.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    Text("All-day events and declined invitations are hidden.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }.padding(22)
        }.frame(maxHeight: .infinity)
    }

    private func meetingDetail(_ meeting: Meeting, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(MeetingLogic.statusText(for: meeting, now: now).uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(PanelStyle.accent)
                    Text(meeting.title).font(.system(size: 21, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 16)
                    VStack(alignment: .leading, spacing: 12) {
                        detailLine("calendar", title: meeting.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                   subtitle: timeRange(meeting))
                        detailLine("circle.fill", title: meeting.calendarTitle, subtitle: "", color: Color(hex: meeting.colorHex))
                        if let location = meeting.location, !location.isEmpty {
                            detailLine("mappin", title: MeetingLogic.joinURL(from: [location]) != nil ? "Online meeting" : location, subtitle: "Location")
                        }
                        if let url = meeting.joinURL {
                            detailLine("video", title: videoProvider(url), subtitle: "")
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(PanelStyle.card, in: RoundedRectangle(cornerRadius: 15))
                    attendeesSection(meeting.attendees).padding(.top, 16).padding(.bottom, 16)
                }
            }.frame(maxHeight: .infinity)
            if let url = meeting.joinURL {
                Button { if !store.isDemo { NSWorkspace.shared.open(url) } } label: {
                    HStack {
                        Image(systemName: "video")
                        Text("Join meeting")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }.buttonStyle(JoinButtonStyle()).disabled(store.isDemo)
            }
            Button { openCalendarSelection(meeting) } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text("Open Calendar")
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                }
            }.buttonStyle(QuietButtonStyle()).padding(.top, 10).disabled(store.isDemo)
                .help("Select this meeting in Apple Calendar")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func attendeesSection(_ attendees: [Attendee]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Attendees").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !attendees.isEmpty {
                    Text("\(attendees.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if attendees.isEmpty {
                Text("No attendee details available.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(attendees) { attendee in
                        AttendeeRow(attendee: attendee)
                        if attendee.id != attendees.last?.id {
                            Rectangle().fill(PanelStyle.rule).frame(height: 1).padding(.horizontal, 12)
                        }
                    }
                }.background(PanelStyle.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func openCalendarSelection(_ meeting: Meeting? = nil) {
        guard !store.isDemo else { return }
        if let target = meeting ?? selectedMeeting ?? MeetingLogic.nextMeeting(store.meetings, now: Date()) {
            let request = navigation.beginCalendarOpen()
            Task {
                let opened = await AppActions.openCalendar(meeting: target)
                navigation.completeCalendarOpen(request, opened: opened)
            }
        } else {
            AppActions.openCalendar()
        }
    }

    private func detailLine(_ icon: String, title: String, subtitle: String, color: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: icon == "circle.fill" ? 8 : 14)).foregroundStyle(color)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    private func footer(now: Date) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(PanelStyle.rule).frame(height: 1)
            if let error = navigation.calendarOpenError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 10)
            }
            HStack(spacing: 5) {
                Circle().fill(store.access == .granted ? PanelStyle.accent : Color.secondary.opacity(0.5))
                    .frame(width: 4, height: 4)
                Text(footerText(now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { openCalendarSelection() } label: {
                    HStack(spacing: 4) {
                        Text("Calendar")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }.font(.system(size: 10, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.isDemo)
                    .help("Show the selected or next meeting in Apple Calendar")
            }.padding(.horizontal, 16).frame(height: 40)
        }
    }

    private var calendarSources: [String] { Array(Set(store.calendars.map(\.source))).sorted() }

    private func footerText(now: Date) -> String {
        if store.isDemo { return "Sample meetings · Preview mode" }
        if store.access != .granted { return "Waiting for calendar access" }
        if store.isRefreshing { return "Updating calendars…" }
        if store.errorMessage != nil { return "Calendar update failed" }
        guard let refreshed = store.lastRefreshed else { return "Connected to Apple Calendar" }
        let minutes = max(0, Int(now.timeIntervalSince(refreshed) / 60))
        return minutes == 0 ? "Updated just now" : "Updated \(minutes) min ago"
    }

    private func grouped(_ meetings: [Meeting]) -> [(date: Date, meetings: [Meeting])] {
        let groups = Dictionary(grouping: meetings) { Calendar.current.startOfDay(for: $0.startDate) }
        return groups.keys.sorted().map { (date: $0, meetings: groups[$0]!) }
    }
}

private struct AttendeeRow: View {
    let attendee: Attendee

    private var roleText: String {
        var parts: [String] = []
        if attendee.isOrganizer { parts.append("Organizer") }
        if attendee.isCurrentUser { parts.append("You") }
        if attendee.role == .optional && !attendee.isOrganizer { parts.append("Optional") }
        return parts.joined(separator: " · ")
    }

    private var responseColor: Color {
        switch attendee.response {
        case .accepted, .completed: return .green
        case .declined: return .red
        case .tentative: return .orange
        default: return .secondary
        }
    }

    private var responseIcon: String {
        switch attendee.response {
        case .accepted, .completed: return "checkmark.circle"
        case .declined: return "xmark.circle"
        case .tentative: return "minus.circle"
        case .delegated: return "arrow.right.circle"
        case .inProcess: return "clock"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(attendee.displayName).font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !roleText.isEmpty {
                    Text(roleText).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: responseIcon).font(.system(size: 12)).foregroundStyle(responseColor)
                Text(attendee.response.displayText).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.top, 2).fixedSize()
        }.padding(12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([attendee.displayName, roleText, attendee.response.displayText].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

private struct MeetingRow: View {
    let meeting: Meeting
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(meeting.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    Text("\(max(1, Int(meeting.endDate.timeIntervalSince(meeting.startDate) / 60))) min")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }.frame(width: 58, alignment: .trailing)
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: meeting.colorHex))
                    .frame(width: 3, height: 31)
                VStack(alignment: .leading, spacing: 5) {
                    Text(meeting.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(meeting.calendarTitle).lineLimit(1)
                        if meeting.startDate <= now && meeting.endDate > now {
                            Text("· Now").foregroundStyle(PanelStyle.accent)
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: meeting.joinURL == nil ? "chevron.right" : "video")
                    .font(.system(size: meeting.joinURL == nil ? 9 : 11)).foregroundStyle(.tertiary)
                    .frame(width: 15)
            }.padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
        }.buttonStyle(RowButtonStyle())
            .accessibilityLabel("\(meeting.title), \(timeRange(meeting)), \(meeting.calendarTitle)")
            .accessibilityHint("Show meeting details")
    }
}

private struct JoinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PanelStyle.accent)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(PanelStyle.accent.opacity(configuration.isPressed ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(11).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.secondary).frame(width: 27, height: 27)
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
    }
}

extension Color {
    init(hex: String) {
        let string = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(string, radix: 16) ?? 0x438E75
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}

private func timeRange(_ meeting: Meeting) -> String {
    "\(meeting.startDate.formatted(date: .omitted, time: .shortened)) – \(meeting.endDate.formatted(date: .omitted, time: .shortened))"
}

private func dayLabel(_ date: Date, now: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return "TODAY" }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "TOMORROW" }
    return date.formatted(.dateTime.weekday(.wide)).uppercased()
}

private func countdownNumber(_ meeting: Meeting, now: Date) -> String {
    if meeting.startDate <= now { return "Now" }
    let minutes = max(1, Int(ceil(meeting.startDate.timeIntervalSince(now) / 60)))
    if minutes < 60 { return "\(minutes)" }
    let hours = minutes / 60
    return minutes % 60 == 0 ? "\(hours)" : "\(hours)h \(minutes % 60)"
}

private func countdownUnit(_ meeting: Meeting, now: Date) -> String {
    if meeting.startDate <= now { return "in progress" }
    let minutes = max(1, Int(ceil(meeting.startDate.timeIntervalSince(now) / 60)))
    return minutes >= 60 && minutes % 60 == 0 ? "hr until next meeting" : "min until next meeting"
}

private func videoProvider(_ url: URL) -> String {
    let host = url.host?.lowercased() ?? ""
    if host.contains("zoom") { return "Zoom" }
    if host.contains("meet.google") { return "Google Meet" }
    if host.contains("teams") { return "Microsoft Teams" }
    if host.contains("webex") { return "Webex" }
    return host
}
