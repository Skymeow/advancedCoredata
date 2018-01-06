import UIKit
import CoreData

class JournalListViewController: UITableViewController {

  // MARK: Properties
  var coreDataStack: CoreDataStack!
  var fetchedResultsController: NSFetchedResultsController<JournalEntry> = NSFetchedResultsController()

  // MARK: IBOutlets
  @IBOutlet weak var exportButton: UIBarButtonItem!

  // MARK: View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()

    configureView()
  }

  // MARK: Navigation
//  segueing from the main list view to the journal detail view.
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    // if detected segue is detaillist, set destination to be detail list
    if segue.identifier == "SegueListToDetail" {
      guard let navigationController = segue.destination as? UINavigationController,
        let detailViewController = navigationController.topViewController as? JournalEntryViewController,
        let indexPath = tableView.indexPathForSelectedRow else {
          fatalError("Application storyboard mis-configuration")
      }
      // get the selected journyentry by user
      let surfJournalEntry =
        fetchedResultsController.object(at: indexPath)
  // MARK: Using Child Contexts for Sets of Edits
      // Need to pass both (managed object) and the (managed object context), caz managed objects only have a weak reference to the context
      // otherwise ARC will remove the context from memory
      let childContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
      childContext.parent = coreDataStack.mainContext
      
      let childEntry = childContext.object(with: surfJournalEntry.objectID) as! JournalEntry
      
      detailViewController.journalEntry = childEntry
      detailViewController.context = childContext
      // the delegate is To inform user has finished editing detail list
      detailViewController.delegate = self

    } else if segue.identifier == "SegueListToDetailAdd" {

      guard let navigationController = segue.destination as? UINavigationController,
        let detailViewController = navigationController.topViewController as? JournalEntryViewController else {
          fatalError("Application storyboard mis-configuration")
      }
      //   creates a new JournalEntry entity instead of retrieving an existing one
      let newJournalEntry = JournalEntry(context: coreDataStack.mainContext)
      
      detailViewController.journalEntry = newJournalEntry
      detailViewController.context = newJournalEntry.managedObjectContext
      detailViewController.delegate = self
    }
  }
}

// MARK: IBActions
extension JournalListViewController {

  @IBAction func exportButtonTapped(_ sender: UIBarButtonItem) {
    exportCSVFile()
  }
}

// MARK: Private
private extension JournalListViewController {

  func configureView() {
    fetchedResultsController = journalListFetchedResultsController()
  }

  func exportCSVFile() {
    navigationItem.leftBarButtonItem = activityIndicatorBarButtonItem()
    // creates and executes the code block on that private context
    coreDataStack.storeContainer.performBackgroundTask { context in
      var results: [JournalEntry] = []
      do {
        results = try context.fetch(self.surfJournalFetchRequest())
      } catch let error as NSError {
        print("Err: \(error.localizedDescription)")
      }

    // Next, create the URL for the exported CSV file by appending the file name (“export.csv”) to the output of the NSTemporaryDirectory method.
    let exportFilePath = NSTemporaryDirectory() + "export.csv"
    let exportFileURL = URL(fileURLWithPath: exportFilePath)
    FileManager.default.createFile(atPath: exportFilePath, contents: Data(), attributes: nil)

    //  write the CSV data to disk
    let fileHandle: FileHandle?
    do {
      fileHandle = try FileHandle(forWritingTo: exportFileURL)
    } catch let error as NSError {
      print("ERROR: \(error.localizedDescription)")
      fileHandle = nil
    }

    if let fileHandle = fileHandle {
    //  iterate over all JournalEntry entities, write the UTF8 string to disk using the file handler write() method
      for journalEntry in results {
        fileHandle.seekToEndOfFile()
        guard let csvData = journalEntry
          .csv()
          .data(using: .utf8, allowLossyConversion: false) else {
            continue
        }

        fileHandle.write(csvData)
      }
  
      // close the export file-writing file handler
      fileHandle.closeFile()
      print("Export Path: \(exportFilePath)")
      DispatchQueue.main.async {
        self.navigationItem.leftBarButtonItem = self.exportBarButtonItem()
        self.showExportFinishedAlertView(exportFilePath)
      }
    } else {
      DispatchQueue.main.async {
        self.navigationItem.leftBarButtonItem =
          self.exportBarButtonItem()
      }
    }
  }
}
  
  // MARK: Export
  
  func activityIndicatorBarButtonItem() -> UIBarButtonItem {
    let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
    let barButtonItem = UIBarButtonItem(customView: activityIndicator)
    activityIndicator.startAnimating()
    
    return barButtonItem
  }
  
  func exportBarButtonItem() -> UIBarButtonItem {
    return UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportButtonTapped(_:)))
  }

  func showExportFinishedAlertView(_ exportPath: String) {
    let message = "The exported CSV file can be found at \(exportPath)"
    let alertController = UIAlertController(title: "Export Finished", message: message, preferredStyle: .alert)
    let dismissAction = UIAlertAction(title: "Dismiss", style: .default)
    alertController.addAction(dismissAction)

    present(alertController, animated: true)
  }
}

  // MARK: NSFetchedResultsController
  private extension JournalListViewController {
    
    func journalListFetchedResultsController() -> NSFetchedResultsController<JournalEntry> {
      let fetchedResultController = NSFetchedResultsController(fetchRequest: surfJournalFetchRequest(),
                                                               managedObjectContext: coreDataStack.mainContext,
                                                               sectionNameKeyPath: nil,
                                                               cacheName: nil)
      fetchedResultController.delegate = self
      
      do {
        try fetchedResultController.performFetch()
      } catch let error as NSError {
        fatalError("Error: \(error.localizedDescription)")
      }
      
      return fetchedResultController
    }
    
    func surfJournalFetchRequest() -> NSFetchRequest<JournalEntry> {
      let fetchRequest:NSFetchRequest<JournalEntry> = JournalEntry.fetchRequest()
      fetchRequest.fetchBatchSize = 20
      
      let sortDescriptor = NSSortDescriptor(key: #keyPath(JournalEntry.date), ascending: false)
      fetchRequest.sortDescriptors = [sortDescriptor]
      
      return fetchRequest
    }
  }
  
  // MARK: NSFetchedResultsControllerDelegate
  extension JournalListViewController: NSFetchedResultsControllerDelegate {
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
      tableView.reloadData()
    }
  }
  
  // MARK: UITableViewDataSource
  extension JournalListViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
      return fetchedResultsController.sections?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
      return fetchedResultsController.sections?[section].numberOfObjects ?? 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
      let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! SurfEntryTableViewCell
      configureCell(cell, indexPath: indexPath)
      return cell
    }
    
    private func configureCell(_ cell: SurfEntryTableViewCell, indexPath:IndexPath) {
      let surfJournalEntry = fetchedResultsController.object(at: indexPath)
      cell.dateLabel.text = surfJournalEntry.stringForDate()
      
      guard let rating = surfJournalEntry.rating?.int32Value else { return }
      
      switch rating {
      case 1:
        cell.starOneFilledImageView.isHidden = false
        cell.starTwoFilledImageView.isHidden = true
        cell.starThreeFilledImageView.isHidden = true
        cell.starFourFilledImageView.isHidden = true
        cell.starFiveFilledImageView.isHidden = true
      case 2:
        cell.starOneFilledImageView.isHidden = false
        cell.starTwoFilledImageView.isHidden = false
        cell.starThreeFilledImageView.isHidden = true
        cell.starFourFilledImageView.isHidden = true
        cell.starFiveFilledImageView.isHidden = true
      case 3:
        cell.starOneFilledImageView.isHidden = false
        cell.starTwoFilledImageView.isHidden = false
        cell.starThreeFilledImageView.isHidden = false
        cell.starFourFilledImageView.isHidden = true
        cell.starFiveFilledImageView.isHidden = true
      case 4:
        cell.starOneFilledImageView.isHidden = false
        cell.starTwoFilledImageView.isHidden = false
        cell.starThreeFilledImageView.isHidden = false
        cell.starFourFilledImageView.isHidden = false
        cell.starFiveFilledImageView.isHidden = true
      case 5:
        cell.starOneFilledImageView.isHidden = false
        cell.starTwoFilledImageView.isHidden = false
        cell.starThreeFilledImageView.isHidden = false
        cell.starFourFilledImageView.isHidden = false
        cell.starFiveFilledImageView.isHidden = false
      default :
        cell.starOneFilledImageView.isHidden = true
        cell.starTwoFilledImageView.isHidden = true
        cell.starThreeFilledImageView.isHidden = true
        cell.starFourFilledImageView.isHidden = true
        cell.starFiveFilledImageView.isHidden = true
      }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
      guard case(.delete) = editingStyle else { return }
      
      let surfJournalEntry = fetchedResultsController.object(at: indexPath)
      coreDataStack.mainContext.delete(surfJournalEntry)
      coreDataStack.saveContext()
    }
  }
  
  // MARK: JournalEntryDelegate
  extension JournalListViewController: JournalEntryDelegate {
    
    func didFinish(viewController: JournalEntryViewController, didSave: Bool) {
      
      guard didSave,
        let context = viewController.context,
        context.hasChanges else {
          dismiss(animated: true)
          return
      }
      
      context.perform {
        do {
          try context.save()
        } catch let error as NSError {
          fatalError("Error: \(error.localizedDescription)")
        }
        
        self.coreDataStack.saveContext()
      }
      
      dismiss(animated: true)
    }
}
