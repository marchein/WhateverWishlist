import PhotosUI
import SwiftUI

/// Creating/editing a wish. Pasting a link fills in what the backend could figure out.
struct ItemEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  let wishlistID: String
  let item: Item?
  let onChange: () -> Void

  @State private var title = ""
  @State private var imageUrl = ""
  @State private var priceText = ""
  @State private var currency = "EUR"
  @State private var priority = 3
  @State private var quantity = 1
  @State private var notes = ""
  @State private var links: [String] = []
  @State private var newLink = ""
  @State private var pasted = ""
  @State private var result: ScrapeResult?
  @State private var scraping = false
  @State private var uploading = false
  @State private var saving = false
  @State private var imageFailed = false
  @State private var photo: PhotosPickerItem?
  @State private var confirmingDelete = false
  @State private var attempted = false
  @FocusState private var focus: Field?

  enum Field: Hashable { case paste, title, imageUrl, price, currency, link, notes }

  private var price: Double? { PriceParser.parse(priceText, locale: l10n.locale) }
  private var priceValid: Bool { priceText.trimmed.isEmpty || (price.map { $0 >= 0 && $0 <= 1_000_000_000 } ?? false) }
  private var currencyValid: Bool { currency.trimmed.isEmpty || currency.trimmed.wholeMatch(of: /[A-Za-z]{3}/) != nil }
  private var titleValid: Bool { !title.trimmed.isEmpty }

  /// What the preview shows; follows `imageUrl` after a short pause so typing doesn't start a download
  /// per keystroke.
  @State private var previewURL: URL?

  /// An unchanged saved URL previews the cached copy; a new URL is shown as typed.
  private var resolvedPreviewURL: URL? {
    let url = imageUrl.trimmed
    if url.isEmpty { return nil }
    if let item, item.imageUrl == url, let display = item.displayImageUrl { return model.config.assetURL(display) }
    return model.config.assetURL(url)
  }

  var body: some View {
    NavigationStack {
      Form {
        pasteSection
        if let result { resultSection(result) }
        titleSection
        pictureSection
        detailsSection
        prioritySection
        linksSection
        notesSection
        if item != nil {
          Section {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Label(l10n.t(.editorDeleteWish), systemImage: "trash").frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("editor.delete")
          }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(l10n.t(item == nil ? .editorNewTitle : .editorEditTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }
            .accessibilityIdentifier("editor.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(l10n.t(.commonSave)) { Task { await save() } }
              .fontWeight(.semibold)
              .disabled(uploading)
              .accessibilityIdentifier("editor.save")
          }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(l10n.t(.commonClose)) { focus = nil }
        }
      }
      .alert(l10n.t(.editorDeleteHeader), isPresented: $confirmingDelete) {
        Button(l10n.t(.commonCancel), role: .cancel) {}
        Button(l10n.t(.commonDelete), role: .destructive) { Task { await delete() } }
      } message: {
        Text(l10n.t(.editorDeleteMessage))
      }
      .onChange(of: photo) { _, newValue in
        guard let newValue else { return }
        Task { await upload(newValue) }
      }
      .onChange(of: imageUrl) { imageFailed = false }
      .task(id: imageUrl) {
        // While typing the address, wait for a pause; "Use", uploads and clearing apply at once.
        if focus == .imageUrl {
          try? await Task.sleep(for: .milliseconds(400))
          if Task.isCancelled { return }
        }
        previewURL = resolvedPreviewURL
      }
    }
    .interactiveDismissDisabled(saving || uploading)
    .onAppear(perform: fill)
    .toastHost()
  }

  // MARK: Sections

  private var pasteSection: some View {
    Section {
      HStack {
        TextField(l10n.t(.editorPastePlaceholder), text: $pasted, axis: .vertical)
          .lineLimit(1...3)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .focused($focus, equals: .paste)
          .accessibilityIdentifier("editor.paste")
          .onSubmit { Task { await fetchDetails() } }
        Button {
          Task { await fetchDetails() }
        } label: {
          if scraping {
            ProgressView()
          } else {
            Image(systemName: "sparkles").symbolEffect(.pulse, isActive: !pasted.trimmed.isEmpty)
          }
        }
        .buttonStyle(.borderless)
        .disabled(scraping || pasted.trimmed.isEmpty)
        .accessibilityLabel(l10n.t(.editorPasteFetch))
        .accessibilityIdentifier("editor.fetch")
      }
      PasteButton(payloadType: String.self) { strings in
        guard let text = strings.first, !text.trimmed.isEmpty else { return }
        pasted = text
        Task { await fetchDetails() }
      }
      .labelStyle(.titleAndIcon)
      .disabled(scraping)
    } header: {
      Text(l10n.t(.editorPasteLabel))
    } footer: {
      Text(l10n.t(.editorPasteHelper))
    }
  }

  private func resultSection(_ result: ScrapeResult) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 4) {
        Text(l10n.t(.scrapeYouPasted)).font(.caption.bold())
        Text(result.input).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        if let final = result.finalUrl, final != result.url {
          Text(l10n.t(.scrapeLeadsTo)).font(.caption.bold()).padding(.top, 4)
          Text(final).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
      }

      finding(
        label: l10n.t(.scrapeFieldTitle), found: result.title != nil, guess: result.sources.title?.isGuess == true,
        source: result.sources.title, canUse: result.title != nil && title != result.title,
        use: { title = result.title ?? title }
      ) {
        Text(result.title ?? "")
      }
      finding(
        label: l10n.t(.scrapeFieldImage), found: result.image != nil, guess: false, source: result.sources.image,
        canUse: result.image != nil && imageUrl != result.image, use: { imageUrl = result.image ?? imageUrl }
      ) {
        RemoteImage(url: model.config.assetURL(result.image), contentMode: .fit, maxPointSize: 64)
          .frame(width: 64, height: 64)
          .background(Color.white, in: .rect(cornerRadius: 8))
      }
      finding(
        label: l10n.t(.scrapeFieldPrice), found: result.price != nil, guess: false, source: result.sources.price,
        canUse: result.price != nil && price != result.price, use: { usePrice(result) }
      ) {
        Text(l10n.formatPrice(result.price, currency: result.currency))
      }

      ForEach(Array(result.messages.enumerated()), id: \.offset) { _, message in
        Label(l10n.scrapeMessage(message), systemImage: "info.circle")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if result.status != .ok, let link = result.url, let url = URL(string: link) {
        VStack(alignment: .leading, spacing: 6) {
          Text(l10n.t(.scrapeFillRest)).font(.footnote).foregroundStyle(.secondary)
          Button(l10n.t(.scrapeOpenPage)) { openURL(url) }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
      }
    } header: {
      Label(l10n.t(statusText(result.status)), systemImage: statusIcon(result.status))
        .foregroundStyle(statusColor(result.status))
        .textCase(nil)
        .font(.subheadline.weight(.semibold))
    }
  }

  private func finding(
    label: String, found: Bool, guess: Bool, source: ScrapeSource?, canUse: Bool, use: @escaping () -> Void,
    @ViewBuilder value: () -> some View
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: !found ? "xmark.circle.fill" : guess ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(!found ? Color.secondary : guess ? Color.orange : Color.green)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.subheadline.bold())
        if found {
          value().font(.subheadline)
          if let source, let text = l10n.t(raw: "scrape.source.\(source.rawValue)") {
            Text(text).font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text(l10n.t(.scrapeNotFound)).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      if canUse {
        Button(l10n.t(.scrapeUse)) { withAnimation { use() } }
          .buttonStyle(.borderless)
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("editor.use.\(label)")
      }
    }
  }

  private var titleSection: some View {
    Section {
      TextField(l10n.t(.editorTitle), text: $title, axis: .vertical)
        .lineLimit(1...4)
        .focused($focus, equals: .title)
        .accessibilityIdentifier("editor.title")
        .onChange(of: title) { _, value in if value.count > 300 { title = String(value.prefix(300)) } }
    } header: {
      Text(l10n.t(.editorTitle))
    } footer: {
      HStack {
        if attempted && !titleValid {
          Text(l10n.t(.editorTitleError)).foregroundStyle(.red)
        }
        Spacer()
        Text("\(title.count)/300").monospacedDigit()
      }
    }
  }

  private var pictureSection: some View {
    Section {
      HStack(alignment: .top, spacing: 14) {
        Group {
          if let previewURL, !imageFailed {
            RemoteImage(url: previewURL, contentMode: .fit, maxPointSize: ImageSize.editor) { imageFailed = true }
              .padding(4)
              .background(Color.white)
          } else {
            Image(systemName: "photo").font(.title).foregroundStyle(.tertiary)
          }
        }
        .frame(width: 96, height: 96)
        .background(Color(.tertiarySystemFill))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
          if uploading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial)
              .clipShape(.rect(cornerRadius: 16))
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          TextField("https://…", text: $imageUrl)
            .focused($focus, equals: .imageUrl)
            .accessibilityIdentifier("editor.imageUrl")
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.subheadline)
          HStack {
            let uploadTitle = l10n.t(.editorUpload)
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
              Label(uploadTitle, systemImage: "photo.badge.plus")
            }
            .secondaryButtonStyle()
            .controlSize(.small)
            .disabled(uploading)
            if !imageUrl.isEmpty {
              Button(l10n.t(.editorRemove), role: .destructive) { withAnimation { imageUrl = "" } }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
          }
        }
      }
      .padding(.vertical, 4)
    } header: {
      Text(l10n.t(.editorPicture))
    } footer: {
      if imageFailed {
        Text(l10n.t(.editorImageFailed)).foregroundStyle(.orange)
      }
    }
  }

  private var detailsSection: some View {
    Section {
      LabeledContent(l10n.t(.editorPrice)) {
        TextField("0,00", text: $priceText)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .focused($focus, equals: .price)
          .accessibilityIdentifier("editor.price")
          .foregroundStyle(priceValid ? Color.primary : Color.red)
      }
      LabeledContent(l10n.t(.editorCurrency)) {
        TextField("EUR", text: $currency)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .multilineTextAlignment(.trailing)
          .focused($focus, equals: .currency)
          .accessibilityIdentifier("editor.currency")
          .foregroundStyle(currencyValid ? Color.primary : Color.red)
          .onChange(of: currency) { _, value in
            let cleaned = String(value.uppercased().prefix(3))
            if cleaned != value { currency = cleaned }
          }
      }
      Stepper(value: $quantity, in: 1...999) {
        LabeledContent(l10n.t(.editorQuantity)) {
          Text("\(quantity)").monospacedDigit().contentTransition(.numericText())
        }
      }
      .accessibilityIdentifier("editor.quantity")
    } footer: {
      if attempted && (!priceValid || !currencyValid) {
        Text(l10n.t(.editorCheckFields)).foregroundStyle(.red)
      }
    }
  }

  private var prioritySection: some View {
    Section(l10n.t(.editorPriority)) {
      PriorityStars(value: priority, showLabel: true) { level in
        withAnimation(.snappy) { priority = level }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var linksSection: some View {
    Section(l10n.t(.editorLinks)) {
      ForEach(links, id: \.self) { link in
        HStack {
          Image(systemName: "link").foregroundStyle(.secondary)
          VStack(alignment: .leading) {
            if let url = URL(string: link) {
              Link(AppHostname.of(link), destination: url).font(.subheadline.weight(.medium))
            }
            Text(link).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Button {
            withAnimation { links.removeAll { $0 == link } }
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(l10n.t(.editorRemoveLink))
        }
      }
      .onDelete { links.remove(atOffsets: $0) }
      .onMove { links.move(fromOffsets: $0, toOffset: $1) }

      HStack {
        TextField(l10n.t(.editorAddLinkPlaceholder), text: $newLink)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.done)
          .focused($focus, equals: .link)
          .accessibilityIdentifier("editor.newLink")
          .onSubmit(addLink)
        Button(action: addLink) {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.borderless)
        .disabled(newLink.trimmed.isEmpty || links.count >= 20)
        .accessibilityLabel(l10n.t(.editorAddLink))
        .accessibilityIdentifier("editor.addLink")
      }
    }
  }

  private var notesSection: some View {
    Section {
      TextField(l10n.t(.editorNotesPlaceholder), text: $notes, axis: .vertical)
        .lineLimit(3...10)
        .focused($focus, equals: .notes)
        .accessibilityIdentifier("editor.notes")
        .onChange(of: notes) { _, value in if value.count > 2000 { notes = String(value.prefix(2000)) } }
    } header: {
      Text(l10n.t(.editorNotes))
    } footer: {
      HStack {
        Spacer()
        Text("\(notes.count)/2000").monospacedDigit()
      }
    }
  }

  // MARK: Scrape status

  private func statusText(_ status: ScrapeResult.Status) -> TKey {
    switch status {
    case .ok: .scrapeStatusOk
    case .partial: .scrapeStatusPartial
    case .failed: .scrapeStatusFailed
    }
  }

  private func statusIcon(_ status: ScrapeResult.Status) -> String {
    switch status {
    case .ok: "checkmark.circle.fill"
    case .partial: "exclamationmark.triangle.fill"
    case .failed: "exclamationmark.octagon.fill"
    }
  }

  private func statusColor(_ status: ScrapeResult.Status) -> Color {
    switch status {
    case .ok: .green
    case .partial: .orange
    case .failed: .red
    }
  }

  // MARK: Actions

  private func fill() {
    guard let item, title.isEmpty else { return }
    title = item.title
    imageUrl = item.imageUrl ?? ""
    priceText = PriceParser.format(item.price, locale: l10n.locale)
    currency = item.currency ?? "EUR"
    priority = item.priority
    quantity = item.quantity
    notes = item.notes ?? ""
    links = item.links
  }

  private func fetchDetails() async {
    let input = pasted.trimmed
    guard !input.isEmpty, !scraping else { return }
    scraping = true
    focus = nil
    defer { scraping = false }
    do {
      let result = try await model.api.scrape(input)
      withAnimation {
        fillEmptyFields(result)
        self.result = result
      }
      pasted = ""
    } catch {
      model.show(error: error)
    }
  }

  /// Never overwrites what the user already entered; the result offers "Use" buttons for that.
  private func fillEmptyFields(_ result: ScrapeResult) {
    if let value = result.title, title.trimmed.isEmpty { title = String(value.prefix(300)) }
    if let value = result.image, imageUrl.isEmpty { imageUrl = value }
    if result.price != nil, priceText.trimmed.isEmpty { usePrice(result) }
    if let link = result.url, !links.contains(link) { links.append(link) }
  }

  private func usePrice(_ result: ScrapeResult) {
    guard let value = result.price else { return }
    priceText = PriceParser.format(value, locale: l10n.locale)
    if let resultCurrency = result.currency { currency = resultCurrency }
  }

  private func upload(_ selection: PhotosPickerItem) async {
    uploading = true
    defer {
      uploading = false
      photo = nil
    }
    do {
      guard let data = try await selection.loadTransferable(type: Data.self) else { return }
      let image = try await Task.detached(priority: .userInitiated) { try ImagePreparer.prepare(data) }.value
      let response = try await model.api.uploadImage(image)
      withAnimation { imageUrl = response.url }
    } catch {
      model.show(error: error)
    }
  }

  private func addLink() {
    let value = newLink.trimmed
    guard !value.isEmpty else { return }
    let candidate = value.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil
      ? value : "https://\(value)"
    guard let url = URL(string: candidate), url.host()?.contains(".") == true || url.host() == "localhost" else {
      model.show(errorMessage: l10n.t(.editorInvalidLink))
      return
    }
    if !links.contains(candidate) { withAnimation { links.append(candidate) } }
    newLink = ""
  }

  private func save() async {
    attempted = true
    guard titleValid, priceValid, currencyValid else {
      model.show(errorMessage: l10n.t(titleValid ? .editorCheckFields : .editorTitleRequired))
      return
    }
    let input = ItemInput(
      title: title.trimmed,
      notes: notes.trimmed.isEmpty ? nil : notes.trimmed,
      imageUrl: imageUrl.trimmed.isEmpty ? nil : imageUrl.trimmed,
      price: price.map { ($0 * 100).rounded() / 100 },
      currency: currency.trimmed.isEmpty ? nil : currency.trimmed.uppercased(),
      priority: priority,
      quantity: quantity,
      links: links)

    saving = true
    defer { saving = false }
    do {
      if let item {
        _ = try await model.api.updateItem(wishlistID: wishlistID, itemID: item.id, input)
      } else {
        _ = try await model.api.createItem(wishlistID: wishlistID, input)
      }
      onChange()
      dismiss()
    } catch {
      model.show(error: error)
    }
  }

  private func delete() async {
    guard let item else { return }
    do {
      try await model.api.deleteItem(wishlistID: wishlistID, itemID: item.id)
      onChange()
      dismiss()
    } catch {
      model.show(error: error)
    }
  }
}

/// Accepts "12,99", "12.99", "1.234,56" and "1,234.56".
nonisolated enum PriceParser {
  static func parse(_ text: String, locale: Locale) -> Double? {
    var value = text.trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.,-").inverted)
    guard !value.isEmpty else { return nil }
    let lastComma = value.lastIndex(of: ",")
    let lastDot = value.lastIndex(of: ".")
    switch (lastComma, lastDot) {
    case (let comma?, let dot?):
      let decimal: Character = comma > dot ? "," : "."
      let grouping: Character = decimal == "," ? "." : ","
      value = value.replacingOccurrences(of: String(grouping), with: "").replacingOccurrences(of: String(decimal), with: ".")
    case (_?, nil):
      value = value.replacingOccurrences(of: ",", with: ".")
    default:
      break
    }
    guard value.filter({ $0 == "." }).count <= 1 else { return nil }
    return Double(value)
  }

  static func format(_ price: Double?, locale: Locale) -> String {
    guard let price else { return "" }
    return price.formatted(.number.precision(.fractionLength(price.rounded() == price ? 0...0 : 2...2)).grouping(.never).locale(locale))
  }
}
