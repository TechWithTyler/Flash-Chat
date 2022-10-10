//
//  LoginViewController.swift
//  Flash Chat iOS13
//
//  Created by Angela Yu on 21/10/2019.
//  Copyright © 2019 Angela Yu. All rights reserved.
//

import UIKit
import Firebase

class LoginViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var emailTextfield: UITextField!

    @IBOutlet weak var passwordTextfield: UITextField!

	override func viewDidLoad() {
		super.viewDidLoad()
		emailTextfield.delegate = self
		passwordTextfield.delegate = self
		emailTextfield.becomeFirstResponder()
	}

    @IBAction func loginPressed(_ sender: Any) {
		if let email = emailTextfield?.text,
		   let password = passwordTextfield?.text {
			Auth.auth().signIn(withEmail: email, password: password) { [self] authResult, error in
				if let error = error {
					// Handle error
					AppDelegate.showError(error, inViewController: self)
				} else {
					// Navigate to ChatViewController
					performSegue(withIdentifier: Constants.loginSegue, sender: self)
				}
			}
		}

	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if emailTextfield.isEditing {
			emailTextfield.endEditing(true)
			passwordTextfield.becomeFirstResponder()
		} else if passwordTextfield.isEditing {
			loginPressed(textField)
		}
		return true
	}
    
}
