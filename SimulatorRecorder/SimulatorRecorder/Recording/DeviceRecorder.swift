//
//  DeviceRecorder.swift
//  SimulatorRecorder
//
//  Created by Grigory Entin on 18/08/2018.
//  Copyright © 2018 Grigory Entin. All rights reserved.
//

import Foundation

class DeviceRecorder : NSObject {
	@objc dynamic var process: Process?
	
	enum RecordingError : Error {
		case missingRecorderExecutable
		case badProcessTerminationStatus(Int32)
	}
	
	@objc dynamic var readyToRecord: Bool {
		return process == nil
	}
	@objc dynamic class var keyPathsForValuesAffectingReadyToRecord: Set<String> {
		return [
			#keyPath(process)
		]
	}
	
	@objc dynamic var recording: Bool {
		return !readyToRecord && !interrupting && !terminated
	}
	@objc dynamic class var keyPathsForValuesAffectingRecording: Set<String> {
		return [
			#keyPath(readyToRecord),
			#keyPath(interrupting),
			#keyPath(terminated)
		]
	}
	
	@objc dynamic var interrupting: Bool = false
	@objc dynamic var terminated: Bool = false
	
	func stopRecording(completionHandler: @escaping (Error?) -> Void) {
		guard let process = process else {
			assert(false)
			return
		}
		
		assert(!interrupting)
		interrupting = true
		process.interrupt()
		DispatchQueue.global().async {
			process.waitUntilExit()
			DispatchQueue.main.async { [weak self] in
				self?.interrupting = false
				completionHandler(nil)
			}
		}
	}
	
	func completeRecording(completionHandler: (Error?) -> Void) {
		guard let process = process else {
			assert(false)
			return
		}
		
		defer {
			self.process = nil
			interrupting = false
		}
		
		let terminationStatus = process.terminationStatus
		
		guard 0 == terminationStatus else {
			let error = RecordingError.badProcessTerminationStatus(terminationStatus)
			completionHandler(error)
			return
		}
		
		completionHandler(nil)
	}
	
	func recorderExecutableURL() throws -> URL {
		let recorderExecutableURL = try throwify(Bundle(for: type(of: self)).url(forResource: "recordVideo", withExtension: ""))
		return recorderExecutableURL
	}
	
	func startRecording(_ device: SimulatorDeviceInfo, terminationHandler: @escaping (Error?) -> Void) {
		do {
			let recorderExecutableURL = try self.recorderExecutableURL()
			
			let process = Process() ≈ {
				$0.executableURL = recorderExecutableURL
				let extraEnvironment = [
					"APP_BUNDLE": Bundle.main.bundlePath
				]
				$0.environment = ProcessInfo().environment.merging(extraEnvironment, uniquingKeysWith: { $1 })
				$0.arguments = [
					device.udid,
					device.name,
					device.osVersion
				]
			}
			process.terminationHandler = { (process) in
				DispatchQueue.main.async {
					assert(self.process == process)
					self.completeRecording(completionHandler: terminationHandler)
				}
			}
			
			self.process = process
			
			try process.run()
		} catch {
			terminationHandler(error)
		}
	}
}
