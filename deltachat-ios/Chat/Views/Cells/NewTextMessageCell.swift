import Foundation
import DcCore
import UIKit

class NewTextMessageCell: BaseMessageCell {

    lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    override func setupSubviews() {
        super.setupSubviews()
        mainContentView.addArrangedSubview(messageLabel)
        mainContentView.axis = .horizontal
        
    }

    override func update(msg: DcMsg, messageStyle: UIRectCorner) {
        messageLabel.text = msg.text
        super.update(msg: msg, messageStyle: messageStyle)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = nil
        messageLabel.attributedText = nil
    }
    
}