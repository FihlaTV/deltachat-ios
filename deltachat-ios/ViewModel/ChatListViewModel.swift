import UIKit

// MARK: - ChatListViewModelProtocol
protocol ChatListViewModelProtocol: class, UISearchResultsUpdating {

    var onChatListUpdate: VoidFunction? { get set }

    var isArchive: Bool { get }

    var numberOfSections: Int { get }
    func numberOfRowsIn(section: Int) -> Int
    func cellDataFor(section: Int, row: Int) -> AvatarCellViewModel

    func msgIdFor(row: Int) -> Int?
    func chatIdFor(section: Int, row: Int) -> Int? // needed to differentiate betweeen deaddrop / archive / default

    // search related
    var searchActive: Bool { get }
    func beginSearch()
    func endSearch()
    func titleForHeaderIn(section: Int) -> String? // only visible on search results
    
    /// returns ROW of table
    func deleteChat(chatId: Int) -> Int
    func archiveChatToggle(chatId: Int)
    func pinChatToggle(chatId: Int)
    func refreshData()

    var numberOfArchivedChats: Int { get }
}

// MARK: - ChatListViewModel
class ChatListViewModel: NSObject, ChatListViewModelProtocol {

    var onChatListUpdate: VoidFunction?

    enum ChatListSectionType {
        case chats
        case contacts
        case messages
    }

    class ChatListSection {
        let type: ChatListSectionType
        var headerTitle: String {
            switch type {
            case .chats:
                return String.localized("pref_chats")
            case .contacts:
                return String.localized("contacts_headline")
            case .messages:
                return String.localized("pref_messages")
            }
        }
        init(type: ChatListSectionType) {
            self.type = type
        }
    }

    var isArchive: Bool
    private let dcContext: DcContext

    var searchActive: Bool = false

    // if searchfield is empty we show default chat list
    private var showSearchResults: Bool {
        return searchActive && searchText.containsCharacters()
    }

    private var chatList: DcChatlist!

    // for search filtering
    private var searchText: String = ""
    private var searchResultChatList: DcChatlist?
    private var searchResultContactIds: [Int] = []
    private var searchResultMessageIds: [Int] = []

    // to manage sections dynamically
    private var searchResultsChatsSection: ChatListSection = ChatListSection(type: .chats)
    private var searchResultsContactsSection: ChatListSection = ChatListSection(type: .contacts)
    private var searchResultsMessagesSection: ChatListSection = ChatListSection(type: .messages)
    private var searchResultSections: [ChatListSection] = []

    init(dcContext: DcContext, isArchive: Bool) {
        dcContext.updateDeviceChats()
        self.isArchive = isArchive
        self.dcContext = dcContext
        super.init()
        updateChatList(notifyListener: true)
    }

    private func updateChatList(notifyListener: Bool) {
        var gclFlags: Int32 = 0
        if isArchive {
            gclFlags |= DC_GCL_ARCHIVED_ONLY
        }
        self.chatList = dcContext.getChatlist(flags: gclFlags, queryString: nil, queryId: 0)
        if notifyListener {
            onChatListUpdate?()
        }
    }

    var numberOfSections: Int {
        if showSearchResults {
            return searchResultSections.count
        }
        return 1
    }

    func numberOfRowsIn(section: Int) -> Int {
        if showSearchResults {
            switch searchResultSections[section].type {
            case .chats:
                return searchResultChatList?.length ?? 0
            case .contacts:
                return searchResultContactIds.count
            case .messages:
                return searchResultMessageIds.count
            }
        }
        return chatList.length
    }

    func cellDataFor(section: Int, row: Int) -> AvatarCellViewModel {
        if showSearchResults {
            switch searchResultSections[section].type {
            case .chats:
                break
            case .contacts:
                return makeContactCellViewModel(contactId: searchResultContactIds[row])
            case .messages:
                return makeMessageCellViewModel(msgId: searchResultMessageIds[row])
            }
        }
        return makeChatCellViewModel(index: row, searchText: searchText)
    }

    func titleForHeaderIn(section: Int) -> String? {
        if showSearchResults {
            return searchResultSections[section].headerTitle
        }
        return nil
    }

    func chatIdFor(section: Int, row: Int) -> Int? {
        let cellData = cellDataFor(section: section, row: row)
        switch cellData.type {
        case .CHAT(let data):
            return data.chatId
        case .CONTACT:
            return nil
        }
    }

    func msgIdFor(row: Int) -> Int? {
        if showSearchResults {
            return nil
        }
        return chatList.getMsgId(index: row)
    }

    func refreshData() {
        updateChatList(notifyListener: true)
    }

    func beginSearch() {
        searchActive = true
    }

    func endSearch() {
        searchText = ""
        searchActive = false
        resetSearch()
    }

    func deleteChat(chatId: Int) -> Int {
        // find index of chatId
        let indexToDelete = Array(0..<chatList.length).filter { chatList.getChatId(index: $0) == chatId }.first
        dcContext.deleteChat(chatId: chatId)
        updateChatList(notifyListener: false)
        safe_assert(indexToDelete != nil)
        return indexToDelete ?? -1
    }

    func archiveChatToggle(chatId: Int) {
        dcContext.archiveChat(chatId: chatId, archive: !self.isArchive)
        updateChatList(notifyListener: false)
    }

    func pinChatToggle(chatId: Int) {
        let chat: DcChat = dcContext.getChat(chatId: chatId)
        let pinned = chat.visibility==DC_CHAT_VISIBILITY_PINNED
        self.dcContext.setChatVisibility(chatId: chatId, visibility: pinned ? DC_CHAT_VISIBILITY_NORMAL : DC_CHAT_VISIBILITY_PINNED)
        updateChatList(notifyListener: false)
    }

    var numberOfArchivedChats: Int {
        let chatList = dcContext.getChatlist(flags: DC_GCL_ARCHIVED_ONLY, queryString: nil, queryId: 0)
        return chatList.length
    }
}

private extension ChatListViewModel {

    /// MARK: - avatarCellViewModel factory
    func makeChatCellViewModel(index: Int, searchText: String) -> AvatarCellViewModel {

        let list: DcChatlist = searchResultChatList ?? chatList

        let chatId = list.getChatId(index: index)
        let chat = dcContext.getChat(chatId: chatId)
        let summary = chatList.getSummary(index: index)
        let unreadMessages = dcContext.getUnreadMessages(chatId: chatId)

        var chatTitleIndexes: [Int] = []
        if searchText.containsCharacters() {
            let chatName = chat.name
            chatTitleIndexes = chatName.containsExact(subSequence: searchText)
        }

        let viewModel = ChatCellViewModel(
            chatData: ChatCellData(
                chatId: chatId,
                summary: summary,
                unreadMessages: unreadMessages
            ),
            titleHighlightIndexes: chatTitleIndexes
        )
        return viewModel
    }

    func makeContactCellViewModel(contactId: Int) -> AvatarCellViewModel {
        let contact = DcContact(id: contactId)
        let nameIndexes = contact.displayName.containsExact(subSequence: searchText)
        let emailIndexes = contact.email.containsExact(subSequence: searchText)
        let chatId: Int? = dcContext.getChatIdByContactId(contactId)
        // contact contains searchText
        let viewModel = ContactCellViewModel(
            contactData: ContactCellData(
                contactId: contact.id,
                chatId: chatId
            ),
            titleHighlightIndexes: nameIndexes,
            subtitleHighlightIndexes: emailIndexes
        )
        return viewModel
    }

    func makeMessageCellViewModel(msgId: Int) -> AvatarCellViewModel {
        let msg: DcMsg = DcMsg(id: msgId)
        let chatId: Int = msg.chatId
        let chat: DcChat = DcChat(id: chatId)
        let summary: DcLot = msg.summary(chat: chat)
        let unreadMessages = dcContext.getUnreadMessages(chatId: chatId)

        let viewModel = ChatCellViewModel(
            chatData: ChatCellData(
                chatId: chatId,
                summary: summary,
                unreadMessages: unreadMessages
            )
        )
        let subtitle = viewModel.subtitle
        viewModel.subtitleHighlightIndexes = subtitle.containsExact(subSequence: searchText)
        return viewModel
    }

    // MARK: - search
    func updateSearchResultSections() {
        var sections: [ChatListSection] = []
        if let chatList = searchResultChatList, chatList.length > 0 {
            sections.append(searchResultsChatsSection)
        }
        if !searchResultContactIds.isEmpty {
            sections.append(searchResultsContactsSection)
        }
        if !searchResultMessageIds.isEmpty {
            sections.append(searchResultsMessagesSection)
        }
        searchResultSections = sections
    }

    func resetSearch() {
        searchResultChatList = nil
        searchResultContactIds = []
        searchResultMessageIds = []
        updateSearchResultSections()
    }

    func filterContentForSearchText(_ searchText: String) {
           if !searchText.isEmpty {
               filterAndUpdateList(searchText: searchText)
           } else {
               // when search input field empty we show default chatList
               resetSearch()
           }
           onChatListUpdate?()
       }

    func filterAndUpdateList(searchText: String) {

           // #1 chats with searchPattern in title bar
           var flags: Int32 = 0
           flags |= DC_GCL_NO_SPECIALS
           searchResultChatList = dcContext.getChatlist(flags: flags, queryString: searchText, queryId: 0)

           // #2 contacts with searchPattern in name or in email
           searchResultContactIds = dcContext.getContacts(flags: DC_GCL_ADD_SELF, queryString: searchText)

           // #3 messages with searchPattern (filtered by dc_core)
           searchResultMessageIds = dcContext.searchMessages(searchText: searchText)
           updateSearchResultSections()
       }
}

// MARK: UISearchResultUpdating
extension ChatListViewModel: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        self.searchText = searchController.searchBar.text ?? ""
        if let searchText = searchController.searchBar.text {
            filterContentForSearchText(searchText)
            return
        }
    }
}