//
//  ThreadListViewController.swift
//  Flash Chat
//
//  Created by TechWithTyler on 10/13/22.
//  Copyright © 2022 Angela Yu. All rights reserved.
//

import UIKit
import Firebase

class ThreadListViewController: UITableViewController {

	@IBOutlet var optionsMenu: UIMenu?

	var threads: [Thread] = []
	
	var selectedThread: Thread? = nil

	var newThreadDate: Date? = nil
	
	let database = Firestore.firestore()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		configureNavigationBar()
		loadThreads()
	}

	func configureNavigationBar() {
		navigationItem.hidesBackButton = true
		navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.circle"), menu: optionsMenu)
	}
	
	func loadThreads() {
		// Add current user to users collection if it doesn't exist. Storing users as a collection allows checking to make sure new threads contain only registered recipients.
		database.collection(Constants.FStore.usersCollectionName)
			.whereField(Constants.FStore.emailField, isEqualTo: (Auth.auth().currentUser?.email)!)
			.getDocuments { [self] snapshot, error in
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
					return
				} else {
					if (snapshot?.documents.isEmpty)! {
						let data: [String : Any] = [
							Constants.FStore.emailField : (Auth.auth().currentUser?.email)!
						]
						database.collection(Constants.FStore.usersCollectionName).addDocument(data: data) { [self] error in
							if let error = error {
								AppDelegate.showError(error, inViewController: self)
							}
						}
					}
				}
			}
		database.collection(Constants.FStore.threadsCollectionName)
			.whereField(Constants.FStore.recipientsField, arrayContains: (Auth.auth().currentUser?.email)!)
			.order(by: Constants.FStore.dateField, descending: true)
			.addSnapshotListener { [self] (querySnapshot, error) in
				guard Auth.auth().currentUser != nil else { return }
				if let error = error {
					AppDelegate.showError(error, inViewController: self)
				} else {
					threads = []
					tableView.reloadData()
					if let snapshotDocuments = querySnapshot?.documents {
						for doc in snapshotDocuments {
							let data = doc.data()
							if let recipients = data[Constants.FStore.recipientsField] as? [String],
							   let date = (data[Constants.FStore.dateField] as? Timestamp)?.dateValue() as? Date,
							   let bubbles = data[Constants.FStore.bubblesField] as? [Message] {
								let newThread = Thread(idString: doc.documentID, date: date, recipients: recipients, messageBubbles: bubbles)
								threads.append(newThread)
								DispatchQueue.main.async { [self] in
									let indexPath = IndexPath(row: threads.count - 1, section: 0)
									tableView?.reloadData()
									tableView?.scrollToRow(at: indexPath, at: .top, animated: true)
								}
							}
						}
					}
				}
			}
	}
	
	@IBAction func addThread(_ sender: UIBarButtonItem) {
		let alert = UIAlertController(title: "New Message", message: "Enter recipient email address. To message multiple recipients, enter their email addresses separated by a space (e.g. email@example.com email@example.com).", preferredStyle: .alert)
		var textField = UITextField()
		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
		let addAction = UIAlertAction(title: "Add", style: .default) { [self] (action) in
			guard let text = textField.text else { return }
			if let messageSender = Auth.auth().currentUser?.email {
				var recipients = text.components(separatedBy: " ")
				recipients.append(messageSender)
				Task {
					await AppDelegate.checkRecipientRegistrationStatus(recipients, inDatabase: database) { [self] registered, error in
						var targetThreadIfDuplicate: Thread? = nil
						if let error = error {
							AppDelegate.showError(error, inViewController: self)
						} else
						if threads.contains(where: { thread in
							targetThreadIfDuplicate = thread
							return thread.recipients.sorted() == recipients.sorted()
						}) {
							DispatchQueue.main.async { [self] in
								selectedThread = targetThreadIfDuplicate
								goToThread()
							}
						}
						else if registered {
							newThreadDate = Date()
							let data: [String : Any] = [
								Constants.FStore.dateField : newThreadDate!,
								Constants.FStore.senderField : messageSender,
								Constants.FStore.bubblesField : [Message](),
								Constants.FStore.recipientsField : recipients
							]
							database.collection(Constants.FStore.threadsCollectionName).addDocument(data: data) { [self] error in
								if let error = error {
									AppDelegate.showError(error, inViewController: self)
								} else {
									loadThreads()
									selectedThread = threads.first!
									DispatchQueue.main.async { [self] in
										goToThread()
									}
								}
							}
						} else {
							let userNotRegistered = UIAlertController(title: "One or more recipients you entered are not registered!", message: "These users need to register with Flash Chat before they can be messaged.", preferredStyle: .alert)
							let okAction = UIAlertAction(title: "OK", style: .default)
							userNotRegistered.addAction(okAction)
							present(userNotRegistered, animated: true)
						}
					}
				}
			}
		}
		alert.addAction(addAction)
		alert.addAction(cancelAction)
		alert.addTextField { alertTextField in
			textField = alertTextField
		}
		textField.keyboardType = .emailAddress
		present(alert, animated: true)
	}
	
	@IBAction func logOutPressed(_ sender: Any) {
		let firebaseAuth = Auth.auth()
		do {
			try firebaseAuth.signOut()
			navigationController?.popToRootViewController(animated: true)
		} catch let signOutError as NSError {
			AppDelegate.showError(signOutError, inViewController: self)
		}
	}
	
	@IBAction func deleteUser(_ sender: Any) {
		let alert = UIAlertController(title: "Are you sure you really want to delete this user?", message: "This can't be undone!", preferredStyle: .alert)
		let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { action in
			if let user = Auth.auth().currentUser {
				self.database.collection(Constants.FStore.usersCollectionName).whereField(Constants.FStore.emailField, isEqualTo: user.email!).getDocuments { (userQuerySnapshot, error) in
					if let error = error {
						AppDelegate.showError(error, inViewController: self)
					} else {
						if let userRef = userQuerySnapshot?.documents.first {
							if userRef.data()[Constants.FStore.emailField] as? String == user.email {
								self.database.collection(Constants.FStore.usersCollectionName).document(userRef.documentID).delete { [self]
									error in
									if let error = error {
										AppDelegate.showError(error, inViewController: self)
									}
								}
							}
						}
					}
				}
				user.delete { error in
					if let error = error {
						AppDelegate.showError(error, inViewController: self)
					} else {
						// Account deleted.
						self.navigationController?.popToRootViewController(animated: true)
					}
				}
			}
		}
		let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
		alert.addAction(deleteAction)
		alert.addAction(cancelAction)
		present(alert, animated: true)
	}
	
	// MARK: - Table view data source
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return threads.count
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: Constants.threadCellIdentifier, for: indexPath)
		let row = indexPath.row
		var contentConfiguration = UIListContentConfiguration.cell()
		var recipients = threads[row].recipients
		if recipients == [Auth.auth().currentUser?.email, Auth.auth().currentUser?.email] {
			contentConfiguration.text = "Me"
		} else {
			recipients.removeAll { recipient in
				return recipient == Auth.auth().currentUser?.email
			}
			let separatedRecipients = recipients.joined(separator: ", ")
			contentConfiguration.text = separatedRecipients
		}
		cell.contentConfiguration = contentConfiguration
		cell.accessoryType = .disclosureIndicator
		return cell
	}
	
	// Override to support editing the table view.
	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == .delete {
			// Delete the row from the data source
			deleteThread(at: indexPath.row)
		}
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		// Only go to the selected thread if it exists (i.e. hasn't been deleted from another app instance/device or Firebase).
		selectedThread = threads[indexPath.row]
		goToThread()
	}
	
	func deleteThread(at row: Int) {
		let alert = UIAlertController(title: "Delete this thread?", message: "This will delete all messages from the thread!", preferredStyle: .alert)
		let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [self] action in
			database.collection(Constants.FStore.threadsCollectionName)
				.order(by: Constants.FStore.dateField, descending: true)
				.getDocuments() { (threadQuerySnapshot, error) in
					if let error = error {
						AppDelegate.showError(error, inViewController: self)
					} else {
						if let threads = threadQuerySnapshot?.documents {
							for thread in threads {
								if thread == threads[row] {
									self.database.collection(Constants.FStore.threadsCollectionName).document(thread.documentID).collection(Constants.FStore.bubblesField)
										.getDocuments { bubbleQuerySnapshot, error in
											if let error = error {
												AppDelegate.showError(error, inViewController: self)
											}
											if let bubbles = bubbleQuerySnapshot?.documents {
												for bubble in bubbles {
													self.database.collection(Constants.FStore.threadsCollectionName).document(thread.documentID).collection(Constants.FStore.bubblesField).document(bubble.documentID).delete { [self]
														error in
														if let error = error {
															AppDelegate.showError(error, inViewController: self)
														}
													}
												}
											}
										}
									self.database.collection(Constants.FStore.threadsCollectionName).document(thread.documentID).delete { [self]
										error in
										if let error = error {
											AppDelegate.showError(error, inViewController: self)
										} else {
											tableView.reloadData()
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
	
	// MARK: - Navigation
	
	// In a storyboard-based application, you will often want to do a little preparation before navigation
	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		// Get the new view controller using segue.destination.
		if let chatVC = segue.destination as? ChatViewController {
			// Pass the selected object to the new view controller.
			chatVC.selectedThread = selectedThread ?? threads.filter { $0.date == newThreadDate }.first
			newThreadDate = nil
		}
	}
	
	func goToThread() {
		performSegue(withIdentifier: Constants.threadSegue, sender: self)
	}
	
}
