//
//  WorkerOperation.swift
//  Distributed Hashcracker
//
//  Created by Sebastian Domke  on 10.02.16.
//  Copyright © 2016 Pascal Schönthier. All rights reserved.
//

import Foundation
import Starscream

class WorkerOperation:MasterWorkerOperation {
    
    override init() {
        super.init()
        let notificationName = Constants.NCValues.stopWorker
        notificationCenter.addObserver(self,
            selector: "stopWorkerOperation:",
            name: notificationName,
            object: nil)
    }
    
    override func main() {
        runloop: while true {
            guard run == true else { break runloop }
            if let message = getMessageFromQueue() {
                print("WorkerOperation message from queue message type",message.type)
                switch message.type {
                case .Basic:
                    print("I'm a basic message")
                    decideWhatToDoBasicMessage(message as! BasicMessage)
                    break
                case .Extended:
                    print("I'm a extended message")
                    decideWhatToDoExtendedMessage(message as! ExtendedMessage)
                    break
                }
            } else{
                //print("No message in the queue")
            }
        }
        sleep(1)
        run = true
    }
    
    /*
    Decision functions
    */
    
    func decideWhatToDoBasicMessage(message: BasicMessage){
        let messageHeader = message.status
        
        switch messageHeader {
        case MessagesHeader.stillAlive:
            stillAlive(message)
            break
        default:
            print("No matching basic header")
            break
        }
    }

    func decideWhatToDoExtendedMessage(message: ExtendedMessage){
        let messageHeader = message.status
        
        switch messageHeader {
        case MessagesHeader.setupConfig:
            setupConfig(message)
            break
        case MessagesHeader.newWorkBlog:
            newWorkBlog(message)
            break
        default:
            print("No matching extended header")
            break
        }
    }
    
    
    /*
    Worker related Message reactions 
    */
    
    /**
     Reaction of a client on a setupConfigMessage ->
     - save the selected hash algorithm, the target hash and the worker_id
     precondition = setupConfigMessage with values : {algorithm, target, worker_id}
     postcondition = client has send a finishedWorkMessage to the server
     */
    func setupConfig(message:ExtendedMessage){
        print("setupConfig")
        
        let workerIDFromMessage = message.values["worker_id"]!
        
        // check if worker is in queue
        guard let worker = WorkerQueue.sharedInstance.getFirstWorker() else { return }
        
        // check if workerID is the id of this worker
        guard worker.checkWorkerID(workerIDFromMessage) else { return }
        
        WorkerQueue.sharedInstance.remove(worker.id)
        worker.algorithm = message.values["algorithm"]!
        worker.target = message.values["target"]!
        WorkerQueue.sharedInstance.put(worker)
        
        //Send finishedWorkMessage
        notificationCenter.postNotificationName(Constants.NCValues.sendMessage,
            object: BasicMessage(status: MessagesHeader.finishedWork, value: worker.id))
    }
    
    /**
     Reaction of a client on a newWorkBlogMessage ->
     - client calculats hash values of the array with the new target passwords and checks if the target hash was found
     precondition = newWorkBlogMessage with a array of the new target passwords
     postcondition = calculated and checked hash values -> if(target hash was hit){send hitTargetHashMessage with the hash, the password, the time needed and the worker_id to the server} else {send finishedWorkMessage with the worker_id to the server}
     */
    func newWorkBlog(message:ExtendedMessage){
        print("newWorkBlog")
        
        let workerIDFromMessage = message.values["worker_id"]!
        
        // check if worker is in queue
        guard let worker = WorkerQueue.sharedInstance.getFirstWorker() else { return }
        
        // check if workerID is the id of this worker
        print("worker = \(worker)")
        print("workerIDCheck = \(worker.checkWorkerID(workerIDFromMessage))")
        guard worker.checkWorkerID(workerIDFromMessage) else { return }
        // check other settings
        print(worker.algorithm)
        print(worker.target)
    
        guard let algo = worker.algorithm,
            let tar = worker.target
//            let crackedPW = crackedPassword
            else { return } /// TODO: hier vielleicht neue setupConfig reagieren
        print("nach guards ---------------------------------")
        let passwordArray: [String] = (message.values["hashes"]?.componentsSeparatedByString(","))!
        
        /// TODO: Algorithm from setupConfig
        var hashAlgorithm: HashAlgorithm?
        switch algo {
        case "SHA-128":
            hashAlgorithm = HashSHA()
        case "SHA-256":
            hashAlgorithm = HashSHA256()
        default:
            hashAlgorithm = HashMD5()
            break
        }
        
        if compareHash(hashAlgorithm!, passwordArray: passwordArray, targetHash: tar) {
            print("Found the searched password -> hitTargetHashMessage was send")
        }
        else{
            print("The searched password wasn't there -> finishedWorkMessage was send")
        }
    }
    
    /**
     Reaction of a client on a stillAliveMessage ->
     - send a aliveMessage with his own worker_id
     precondition = stillAliveMessage from the server
     postcondition = aliveMessage was send to the server
     */
    func stillAlive(message:BasicMessage){
        print("stillAlive")
        //Send a stillAliveMessage to the master with the worker_id of the client
        guard let worker = WorkerQueue.sharedInstance.getFirstWorker() else { return }
        notificationCenter.postNotificationName(Constants.NCValues.sendMessage, object: BasicMessage(status: MessagesHeader.alive, value: worker.id))
    }
    
    
    /*
    Helper functions
    */
    
    func getMessageFromQueue() -> Message? {
        return messageQueue.get()
    }
    
    func compareHash(hashAlgorithm: HashAlgorithm, passwordArray:[String], targetHash: String) -> Bool{
        let worker = WorkerQueue.sharedInstance.getFirstWorker()
        
        // <<<<<<<<<< Start time measurement
        let startTimeMeasurement = NSDate();
        
        for password in passwordArray{
            
            let hashedPasswordFromArray = hashAlgorithm.hash(string: password)
            
            if(hashedPasswordFromArray == targetHash){
                print("Found the searched password! \(hashedPasswordFromArray) == \(targetHash) -> Password = \(password))")
                
                let hitTargetHashValues: [String:String] = ["hash": targetHash, "password": password, /*"time_needed": "ka", */"worker_id": worker!.id]
                notificationCenter.postNotificationName(Constants.NCValues.sendMessage,
                    object: ExtendedMessage(status: MessagesHeader.hitTargetHash, values: hitTargetHashValues))
                return true
            }
            else{
                print("\(password) isn't the searched password")
            }
        }
        // <<<<<<<<<<   end time measurement
        let endTimeMeasurement = NSDate();
        // <<<<< Time difference in seconds (double)
        let timeInterval: Double = endTimeMeasurement.timeIntervalSinceDate(startTimeMeasurement);
        
        let hashesPerTime: [String:String] = ["hash_count": String(passwordArray.count), "time_needed": String(timeInterval), /*"time_needed": "ka", */"worker_id": worker!.id]
        
        notificationCenter.postNotificationName(Constants.NCValues.sendMessage,
            object: ExtendedMessage(status: MessagesHeader.hashesPerTime, values: hashesPerTime))
        
        notificationCenter.postNotificationName(Constants.NCValues.sendMessage,
            object: BasicMessage(status: MessagesHeader.finishedWork, value: worker!.id))
        return false
        
    }
    
    func stopWorkerOperation(notification:NSNotification) {
        run = false
    }
    
}
