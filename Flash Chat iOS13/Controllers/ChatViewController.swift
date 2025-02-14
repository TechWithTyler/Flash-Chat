//
//  ChatViewController.swift
//  Flash Chat iOS13
//
//  Created by Angela Yu on 21/10/2019.
//  Copyright © 2019 Angela Yu. All rights reserved.
//

import UIKit
import Firebase

class ChatViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate {

	@IBOutlet weak var sendButton: UIButton?

	@IBOutlet weak var tableView: UITableView?

	@IBOutlet weak var messageTextfield: UITextField?

	let database = Firestore.firestore()

	var messages: [Message] = []

	var selectedThread: Thread? = nil

	var userNotRegisteredPresented: Bool = false

	let messagesForSelectedThread = Constants.FStore.messagesCollectionName

	override func viewDidLoad() {
		super.viewDidLoad()
		if let recipients = selectedThread?.recipients as? [String] {
			title = "\(recipients.count) recipients"
		}
		tableView?.delegate = self
		tableView?.dataSource = self
		messageTextfield?.delegate = self
		tableView?.register(UINib(nibName: Constants.cellNibName, bundle: nil), forCellReuseIdentifier: Constants.bubbleCellIdentifier)
		if let thread = selectedThread {
			loadMessages(for: thread)
		}
	}

	func loadMessages(for thread: Thread) {
		database.collection(Constants.FStore.threadsCollectionName)
			.order(by: Constants.FStore.dateField, descending: false)
			.addSnapshotListener { [self] (querySnapshot, error) in
				guard let snapshotDocuments = querySnapshot?.documents,
					  snapshotDocuments.contains(where: { document in
						  document.documentID == selectedThread?.idString
					  }),
					  let selectedThreadID = selectedThread?.idString else { return }
				loadBubbles(for: selectedThreadID)
			}
	}

	func loadBubbles(for selectedThreadID: String) {
		database.collection(Constants.FStore.threadsCollectionName).document(selectedThreadID).collection(Constants.FStore.bubblesField)
			.order(by: Constants.FStore.dateField, descending: false)
			.addSnapshotListener { [self] (querySnapshot, error) in
				guard Auth.auth().currentUser != nil else { return }
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
				} else {
					messages = []
					tableView?.reloadData()
					guard let snapshotDocuments = querySnapshot?.documents else { return }
					for doc in snapshotDocuments {
						let data = doc.data()
						guard let sender = data[Constants.FStore.senderField] as? String,
							  let recipients = selectedThread?.recipients as? [String],
							  let date = (data[Constants.FStore.dateField] as? Timestamp)?.dateValue() as? Date,
							  let body = data[Constants.FStore.bodyField] as? String else { continue }
						checkRecipientStatusAndAddMessage(sender: sender, recipients: recipients, date: date, body: body, idString: doc.documentID)
					}
				}
			}
	}

	func checkRecipientStatusAndAddMessage(sender: String, recipients: [String], date: Date, body: String, idString: String) {
		Task {
			await AppDelegate.checkRecipientRegistrationStatus(recipients, inDatabase: database) { [self] registered, error in
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
				} else {
					let newMessage = Message(sender: sender, date: date, body: body, idString: idString)
					messages.append(newMessage)
					DispatchQueue.main.async { [self] in
						let indexPath = IndexPath(row: messages.count - 1, section: 0)
						tableView?.reloadData()
						tableView?.scrollToRow(at: indexPath, at: .top, animated: true)
					}
					if !registered && !userNotRegisteredPresented {
						let userNotRegistered = UIAlertController(title: "One or more recipients in this thread are no longer registered!", message: "You can't send new messages in this thread until they re-register.", preferredStyle: .alert)
						let okAction = UIAlertAction(title: "OK", style: .default)
						userNotRegistered.addAction(okAction)
						present(userNotRegistered, animated: true)
						userNotRegisteredPresented = true
						messageTextfield?.isEnabled = false
						sendButton?.isEnabled = false
					}
				}
			}
		}
	}

	@IBAction func sendPressed(_ sender: Any) {
		if let messageBody = messageTextfield?.text,
		   let messageSender = Auth.auth().currentUser?.email {
			let currentDate = Date()
			guard let selectedThread = selectedThread else { return }
			let dataForMessage: [String : Any] = [
				Constants.FStore.senderField : messageSender,
				Constants.FStore.bodyField : messageBody,
				Constants.FStore.dateField : currentDate
			]
			database.collection(Constants.FStore.threadsCollectionName).document((selectedThread.idString)).collection(Constants.FStore.bubblesField).addDocument(data: dataForMessage) { [self] error in
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
				} else {
					database.collection(Constants.FStore.threadsCollectionName).document((selectedThread.idString)).updateData([Constants.FStore.dateField : Date()])
					DispatchQueue.main.async { [self] in
						messageTextfield?.text?.removeAll()
					}
				}
			}
			if selectedThread.recipients == [messageSender, messageSender] {
				DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [self] in
					// Repeat adding of Message object, this time appearing as if it came from someone else.
				let currentDatePlusAFewSeconds = Date()
				let dataForSelfMessageEcho: [String : Any] = [
					Constants.FStore.senderField : String(),
					Constants.FStore.bodyField : messageBody,
					Constants.FStore.dateField : currentDatePlusAFewSeconds
				]
					database.collection(Constants.FStore.threadsCollectionName).document((selectedThread.idString)).collection(Constants.FStore.bubblesField).addDocument(data: dataForSelfMessageEcho) { [self] error in
						if let error = error {
							AppDelegate.showError(error, inViewController: self)
						} else {
							database.collection(Constants.FStore.threadsCollectionName).document((selectedThread.idString)).updateData([Constants.FStore.dateField : Date()])
						}
					}
				}
			}
		}
	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		sendPressed(textField)
		return true
	}

}

extension ChatViewController {

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return messages.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let message = messages[indexPath.row]
		let currentUser = Auth.auth().currentUser?.email
		let cell = tableView.dequeueReusableCell(withIdentifier: Constants.bubbleCellIdentifier, for: indexPath) as? MessageCell
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		let date = message.date
		let dateString = dateFormatter.string(from: date)
		cell?.dateTimeLabel?.text = dateString
		cell?.messageBodyLabel?.text = message.body
		if message.sender == currentUser {
			cell?.senderLabel?.text = nil
			cell?.leftImageView?.isHidden = true
			cell?.rightImageView?.isHidden = false
			cell?.messageBubble?.backgroundColor = UIColor(named: Constants.BrandColors.lightPurple)
			cell?.messageBodyLabel?.textColor = UIColor(named: Constants.BrandColors.purple)
		} else {
			cell?.senderLabel?.text = message.sender
			cell?.leftImageView?.isHidden = false
			cell?.rightImageView?.isHidden = true
			cell?.messageBubble?.backgroundColor = UIColor(named: Constants.BrandColors.purple)
			cell?.messageBodyLabel?.textColor = UIColor(named: Constants.BrandColors.lightPurple)
		}
		return cell!
	}

	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		if messages[indexPath.row].sender == Auth.auth().currentUser?.email {
			return .delete
		} else {
			return .none
		}
	}

	// Override to support editing the table view.
	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == .delete && messages[indexPath.row].sender == Auth.auth().currentUser?.email {
			// Delete the row from the data source
			deleteMessage(at: indexPath.row)
		}
	}

	func deleteMessage(at row: Int) {
		let alert = UIAlertController(title: "Delete this message?", message: "The recipients will no longer see it!", preferredStyle: .alert)
		let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [self] action in
			database.collection(Constants.FStore.threadsCollectionName).document((selectedThread?.idString)!).collection(Constants.FStore.bubblesField)
				.order(by: Constants.FStore.dateField, descending: false).getDocuments() { (querySnapshot, error) in
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
				} else {
					if let bubbles = querySnapshot?.documents {
						for bubble in bubbles {
							let bubbleBeingChecked = bubble.documentID
							let bubbleAtSwipedRow = bubbles[row].documentID
							if bubbleBeingChecked == bubbleAtSwipedRow {
								self.database.collection(Constants.FStore.threadsCollectionName).document((self.selectedThread?.idString)!).collection(Constants.FStore.bubblesField).document(bubble.documentID).delete { [self]
									error in
									if let error = error {
										AppDelegate.showError(error, inViewController: self)
									} else {
										tableView?.reloadData()
									}
								}
							}
						}
					}
				}
			}
		}
		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
		alert.addAction(deleteAction)
		alert.addAction(cancelAction)
		present(alert, animated: true)
	}


}
