// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit
import PhotosUI

/// The classic modal composer. Cancel fixed left, Send fixed right, always.
final class ComposeViewController: UIViewController,
                                  UITableViewDataSource, UITableViewDelegate,
                                  PHPickerViewControllerDelegate {

    private let repository: MailRepository
    private var draft: Draft

    /// Fired when the Drafts folder has changed underneath, so whatever is
    /// showing it can catch up.
    var onDraftsChanged: (() -> Void)?

    private let toField = UITextField()
    private let ccField = UITextField()
    private let bccField = UITextField()
    /// One row per attached file, rebuilt whenever the list changes.
    private let attachmentsStack = UIStackView()
    private let subjectField = UITextField()
    private let bodyView = UITextView()
    private var ccVisible = false
    /// The Cc row itself, hidden until the toggle is pressed.
    ///
    /// Assigned rather than constructed here because it must be the view
    /// `row()` returns and go STRAIGHT into the stack. It used to be an
    /// empty wrapper with the row dropped inside it by `addSubview`, and
    /// that wrapper made Cc unusable: a plain `addSubview` leaves
    /// `translatesAutoresizingMaskIntoConstraints` true on the row, so the
    /// 44 pt height constraint `row()` installs fought the autoresizing
    /// frame and lost, and nothing ever gave the wrapper a size. The label
    /// still drew, which is why it looked fine — but the field had no
    /// tappable area at all, so pressing Cc quietly did nothing and the
    /// next thing typed went into whichever field still had focus.
    ///
    /// Found by driving the form to send one test letter. A stack's
    /// ARRANGED subviews get their autoresizing turned off for them; a
    /// plain subview does not.
    private var ccRow = UIView()
    /// Built and added exactly like `ccRow`, and for the reason recorded
    /// there: straight into the stack as an ARRANGED subview, never
    /// `addSubview`d into a wrapper.
    private var bccRow = UIView()
    private let ccToggle = UIButton(type: .system)

    /// Addresses offered under the field he is typing in.
    ///
    /// The whole feature turns on one fact: he sends mail
    /// to himself constantly, and he is ninety. Every address was
    /// typed out in full on glass. It also quietly unlocks something
    /// that was impossible before — the email keyboard has no comma, and
    /// `collect()` splits recipients on commas, so a SECOND recipient
    /// could not be typed at all. Choosing from this list inserts the
    /// separator for him.
    private let suggestionsView = UITableView(frame: .zero, style: .plain)
    private var suggestions: [KnownRecipient] = []
    private weak var activeAddressField: UITextField?
    private static let suggestionRowHeight: CGFloat = Theme.suggestionRowHeight

    init(repository: MailRepository, draft: Draft) {
        self.repository = repository
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
        title = draft.subject.isEmpty ? "New Message" : draft.subject
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Send", style: .done, target: self, action: #selector(sendTapped))
        for item in [navigationItem.leftBarButtonItem, navigationItem.rightBarButtonItem] {
            item?.setTitleTextAttributes([.font: Theme.fontBarButton], for: .normal)
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        stack.addArrangedSubview(row(label: "To:", field: toField, text: draft.to.joined(separator: ", ")))
        ccRow = row(label: "Cc:", field: ccField, text: draft.cc.joined(separator: ", "))
        stack.addArrangedSubview(ccRow)
        ccRow.isHidden = true

        // A real field, not a rename. The button has said "Cc/Bcc" since
        // the composer was written and only ever revealed Cc — the app
        // naming something that was not there, the same defect as telling
        // him to go to a Settings screen that did not exist.
        bccRow = row(label: "Bcc:", field: bccField,
                     text: draft.bcc.joined(separator: ", "))
        stack.addArrangedSubview(bccRow)
        bccRow.isHidden = true

        // Cc/Bcc hidden behind an explicit labelled toggle rather than always
        // present: two fewer boxes on screen for someone who will never use
        // them, and still one tap away with a word on it.
        ccToggle.setTitle("Cc/Bcc", for: .normal)
        ccToggle.titleLabel?.font = Theme.fontDetailMeta
        ccToggle.addTarget(self, action: #selector(toggleCc), for: .touchUpInside)
        ccToggle.contentHorizontalAlignment = .left
        let toggleRow = UIView()
        ccToggle.translatesAutoresizingMaskIntoConstraints = false
        toggleRow.addSubview(ccToggle)
        NSLayoutConstraint.activate([
            ccToggle.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: Theme.detailContentInsetLeft),
            ccToggle.topAnchor.constraint(equalTo: toggleRow.topAnchor),
            ccToggle.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor),
            ccToggle.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
        ])
        stack.addArrangedSubview(toggleRow)
        stack.addArrangedSubview(row(label: "Subject:", field: subjectField, text: draft.subject))
        attachmentsStack.axis = .vertical
        attachmentsStack.spacing = 0
        // Zero height, preferred not required — the same guard as
        // `MessageHeaderView`, and for the same reason (B-027). An empty
        // `UIStackView` has no intrinsic height, and this one sits in the
        // chain that gives the header block its height, which is what
        // `bodyView` is pinned beneath. With no photographs attached, which
        // is nearly every letter, nothing decided how tall this was, and
        // Auto Layout was free to hand the writing area 0 points the way it
        // did to the reading pane's web view.
        let flatAttachments = attachmentsStack.heightAnchor.constraint(equalToConstant: 0)
        flatAttachments.priority = .defaultLow
        flatAttachments.isActive = true
        stack.addArrangedSubview(attachmentsStack)
        stack.addArrangedSubview(attachRow())
        rebuildAttachments()

        bodyView.font = .systemFont(ofSize: Theme.scaled(17))
        bodyView.text = draft.body
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: Theme.detailContentInsetLeft - 5,
                                                   bottom: 12, right: Theme.detailContentInsetLeft - 5)
        // Smart punctuation off. It turns "--" into an em dash and straight
        // quotes into curly ones behind his back, which is not help.
        bodyView.smartDashesType = .no
        bodyView.smartQuotesType = .no
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bodyView)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: stack.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Last, so it sits above the body it overlaps.
        configureSuggestions()
    }

    /// The permanent "Attach Photo" control.
    ///
    /// A labelled button rather than the callout menu Mail of this era
    /// used, because `BRIEF.md`'s promise is that nothing needs a gesture
    /// beyond tap and ordinary scrolling — and "press and hold in the body
    /// until a menu appears" is exactly the kind of thing that promise
    /// exists to rule out. Always visible, so it never moves.
    private func attachRow() -> UIView {
        let container = UIView()
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "paperclip")
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Theme.detailContentInsetLeft, bottom: 0, trailing: 0)
        var title = AttributedString("Attach Photo")
        title.font = Theme.fontDetailMeta
        config.attributedTitle = title
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [button, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    /// One row per attached file: what it is, what it weighs, and a way to
    /// take it off again.
    ///
    /// Removal exists now and did not before, and the reason is simply
    /// that attaching does. A list you can add to and not subtract from
    /// turns one mis-tap in a photo library into a letter he cannot send
    /// without starting it over.
    private func rebuildAttachments() {
        for view in attachmentsStack.arrangedSubviews {
            attachmentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, attachment) in draft.attachments.enumerated() {
            attachmentsStack.addArrangedSubview(attachmentRow(attachment, at: index))
        }
    }

    private func attachmentRow(_ attachment: DraftAttachment, at index: Int) -> UIView {
        let container = UIView()
        let icon = UIImageView(image: UIImage(systemName: "paperclip"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        label.numberOfLines = 1
        // The weight, not just the name. A refusal at Send is the right
        // backstop but a poor first warning — by then he has written the
        // letter. Saying what it weighs while he attaches it is the cheap
        // half of the same job.
        label.text = attachment.size.map {
            attachment.filename + "  —  "
                + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? attachment.filename

        let remove = UIButton(type: .system)
        remove.setTitle("Remove", for: .normal)
        remove.titleLabel?.font = Theme.fontDetailMeta
        remove.setTitleColor(Theme.destructive, for: .normal)
        remove.tag = index
        remove.addTarget(self, action: #selector(removeAttachment(_:)), for: .touchUpInside)

        let rule = UIView()
        rule.backgroundColor = Theme.separator

        for v in [icon, label, remove, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            remove.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor,
                                            constant: 8),
            remove.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                             constant: -Theme.detailContentInsetLeft),
            remove.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            remove.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.minHitTarget),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                          constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    @objc private func removeAttachment(_ sender: UIButton) {
        guard sender.tag < draft.attachments.count else { return }
        draft.attachments.remove(at: sender.tag)
        rebuildAttachments()
    }

    // MARK: - Choosing a photo

    @objc private func attachTapped() {
        // PHPicker, not the old image picker, and the difference is a
        // permission prompt. PHPicker runs out of process and hands back
        // only what he chose, so it needs no photo-library access at all —
        // which matters because a "Don't Allow" tapped once by a
        // 90-year-old is invisible, permanent, and looks like the button
        // being broken.
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            let suggested = provider.suggestedName ?? "Photo"
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                // Re-encoded as JPEG rather than passed through. iPads
                // store photos as HEIC, which a good many recipients
                // cannot open at all — a letter whose attachment will not
                // display is worse than one with no attachment, because
                // neither end knows. Full resolution is kept: the size
                // ceiling is already refused loudly at send (B-007), so
                // there is no need to quietly shrink what he chose.
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.85) else { return }
                Task { @MainActor in
                    self?.attach(data, named: suggested + ".jpg")
                }
            }
        }
    }

    @MainActor
    private func attach(_ data: Data, named filename: String) {
        // Staged on disk rather than held in the draft: a composer left
        // open for an hour should not also be holding several megabytes of
        // image in memory. Safe against the launch-time purge because a
        // SAVED draft embeds its bytes on the server and reopens as a
        // message part, so nothing on disk has to outlive the session.
        guard let url = try? AttachmentStore.write(data, named: filename) else {
            ErrorPresenter.show(.attachmentFailed, on: self)
            return
        }
        draft.attachments.append(DraftAttachment(source: .localFile(url),
                                                 filename: filename,
                                                 mimeType: "image/jpeg",
                                                 size: Int64(data.count)))
        rebuildAttachments()
    }

    private func row(label text: String, field: UITextField, text value: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = text
        label.font = Theme.fontDetailMeta
        label.textColor = Theme.secondaryText
        field.text = value
        field.font = .systemFont(ofSize: Theme.scaled(17))
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        // Address fields get the EMAIL keyboard, which is the difference
        // between "@" being on the main layer and being hidden two taps deep
        // behind .?123. Found by typing a real address into this form: the
        // key in that position on the default keyboard is a COMMA, so the
        // address came out as "someone,example.org" and would have been
        // rejected as unparseable. A 90-year-old hunting for an @ sign is a
        // reason not to send the letter at all.
        if field === toField || field === ccField || field === bccField {
            field.keyboardType = .emailAddress
            field.addTarget(self, action: #selector(addressEditingChanged(_:)),
                            for: .editingChanged)
            field.addTarget(self, action: #selector(addressEditingBegan(_:)),
                            for: .editingDidBegin)
            field.addTarget(self, action: #selector(addressEditingEnded(_:)),
                            for: .editingDidEnd)
        }

        let rule = UIView()
        rule.backgroundColor = Theme.separator
        for v in [label, field, rule] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 72),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Theme.detailContentInsetLeft),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Theme.minHitTarget),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.detailContentInsetLeft),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    // MARK: - Recipient suggestions

    private func configureSuggestions() {
        suggestionsView.dataSource = self
        suggestionsView.delegate = self
        suggestionsView.rowHeight = Self.suggestionRowHeight
        suggestionsView.backgroundColor = Theme.barFill
        suggestionsView.separatorColor = Theme.separator
        suggestionsView.isHidden = true
        suggestionsView.layer.borderWidth = 0.5
        suggestionsView.layer.borderColor = Theme.separator.cgColor
        suggestionsView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        view.addSubview(suggestionsView)
    }

    @objc private func addressEditingBegan(_ field: UITextField) {
        activeAddressField = field
        refreshSuggestions()
    }

    @objc private func addressEditingChanged(_ field: UITextField) {
        activeAddressField = field
        refreshSuggestions()
    }

    @objc private func addressEditingEnded(_ field: UITextField) {
        // Deferred by one runloop turn: a TAP on a suggestion ends editing
        // before the table sees the touch, so hiding immediately would
        // dismiss the row out from under his finger and nothing would be
        // chosen.
        DispatchQueue.main.async { [weak self] in
            guard let self, !(self.activeAddressField?.isEditing ?? false) else { return }
            self.suggestionsView.isHidden = true
        }
    }

    private func refreshSuggestions() {
        guard let field = activeAddressField else { return }
        let typed = MailFormat.currentRecipientToken(in: field.text ?? "")
        // Anything with an "@" already in it is a finished address, not a
        // half-typed one; offering completions for it is noise.
        suggestions = typed.contains("@")
            ? [] : RecipientBook.shared.suggestions(for: typed)
        suggestionsView.reloadData()
        layoutSuggestions(under: field)
        suggestionsView.isHidden = suggestions.isEmpty
    }

    private func layoutSuggestions(under field: UITextField) {
        guard let row = field.superview,
              let frame = row.superview?.convert(row.frame, to: view) else { return }
        let height = CGFloat(suggestions.count) * Self.suggestionRowHeight
        suggestionsView.frame = CGRect(x: frame.minX, y: frame.maxY,
                                       width: frame.width, height: height)
        view.bringSubviewToFront(suggestionsView)
    }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int {
        suggestions.count
    }

    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "suggestion", for: ip)
        let entry = suggestions[ip.row]
        var config = cell.defaultContentConfiguration()
        config.text = entry.display
        config.textProperties.font = Theme.fontListSender
        config.textProperties.color = Theme.primaryText
        // The address under the name, because two people can share a name
        // and he needs to see which one he is about to write to.
        config.secondaryText = entry.display == entry.address ? nil : entry.address
        config.secondaryTextProperties.font = Theme.fontDetailMeta
        config.secondaryTextProperties.color = Theme.secondaryText
        cell.contentConfiguration = config
        cell.backgroundColor = Theme.barFill
        return cell
    }

    func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        guard let field = activeAddressField, ip.row < suggestions.count else { return }
        field.text = MailFormat.replacingRecipientToken(
            in: field.text ?? "", with: suggestions[ip.row].address)
        t.deselectRow(at: ip, animated: false)
        refreshSuggestions()
    }

    @objc private func toggleCc() {
        ccVisible.toggle()
        ccRow.isHidden = !ccVisible
        bccRow.isHidden = !ccVisible
    }

    @objc private func cancelTapped() {
        // Offer to keep the draft rather than silently discarding typing.
        let hasContent = !(bodyView.text ?? "").isEmpty || !(subjectField.text ?? "").isEmpty
        guard hasContent else { dismiss(animated: true); return }

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        sheet.addAction(UIAlertAction(title: "Save Draft", style: .default) { [weak self] _ in
            guard let self else { return }
            self.collect()
            // Everything the work needs is captured BEFORE dismissing, so
            // the save outlives this window without holding it alive.
            //
            // And the refresh fires AFTER the await, not beside it. Racing
            // them showed the folder mid-save — the replacement appended
            // and the old copy not yet gone — so a saved draft appeared
            // briefly as two near-identical letters. Measured on device:
            // a manual Refresh a moment later showed one, which is how the
            // race was told apart from a replacement that had failed.
            let draft = self.draft
            let repository = self.repository
            let changed = self.onDraftsChanged
            self.dismiss(animated: true)
            Task { @MainActor in
                try? await repository.saveDraft(draft)
                changed?()
            }
        })
        sheet.addAction(UIAlertAction(title: "Delete Draft", style: .destructive) { [weak self] _ in
            guard let self else { return }
            // Deletes the SAVED copy too. Previously this only dismissed
            // the window, so "Delete Draft" on a draft reopened from the
            // Drafts folder left it sitting there — the button said the
            // one thing it did not do.
            let saved = self.draft.savedID
            let repository = self.repository
            let changed = self.onDraftsChanged
            self.dismiss(animated: true)
            guard let saved else { changed?(); return }
            Task { @MainActor in
                try? await repository.deleteDraft(saved)
                changed?()
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func sendTapped() {
        collect()
        Task { @MainActor in
            do {
                try await repository.send(draft)
                // A sent letter must not stay in Drafts. Without this,
                // finishing a draft left the half-written version behind
                // and he would find it again tomorrow, indistinguishable
                // from something still owed.
                if let saved = draft.savedID {
                    try? await repository.deleteDraft(saved)
                }
                onDraftsChanged?()
                dismiss(animated: true)
            } catch {
                // Pass the real reason through. Flattening everything to
                // "Message was not sent." was fine while that was the only
                // thing the layers below could say; now they can distinguish
                // a letter too large to send from a network that dropped,
                // and collapsing the two would throw away the one piece of
                // information that tells him what to do differently.
                //
                // The sheet is deliberately NOT dismissed on failure — the
                // letter he wrote is still in it.
                ErrorPresenter.show(error as? MailError ?? .notSent, on: self)
            }
        }
    }

    private func collect() {
        func addresses(_ s: String?) -> [String] {
            (s ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        // `savedID` is deliberately untouched here: `collect` rebuilds the
        // draft from the form, and the form has no field for which copy on
        // the server this is.
        draft.to = addresses(toField.text)
        draft.cc = addresses(ccField.text)
        draft.bcc = addresses(bccField.text)
        draft.subject = subjectField.text ?? ""
        draft.body = bodyView.text ?? ""
    }
}

#endif
