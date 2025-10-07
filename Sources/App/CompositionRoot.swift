import SwiftUI

/// Root composition view that wires up all dependencies and global overlays
struct CompositionRoot: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    
    var body: some View {
        ContentContainer()
            .environmentObject(appEnvironment)
            // Global UX overlays
            .enhancedToastOverlay(appEnvironment.enhancedToastCenter)
            .errorOverlay(appEnvironment.errorMessageManager)
            .errorToastOverlay(appEnvironment.errorMessageManager)
            // Global sheets
            .sheet(isPresented: $appEnvironment.isShowingOnboarding) {
                OnboardingView()
                    .environmentObject(appEnvironment)
                    .frame(minWidth: 800, minHeight: 560)
            }
            .sheet(isPresented: $appEnvironment.isShowingSettings) {
                SettingsView()
                    .environmentObject(appEnvironment)
                    .frame(minWidth: 720, minHeight: 520)
            }
            .sheet(isPresented: $appEnvironment.isShowingHelp) {
                HelpView()
                    .environmentObject(appEnvironment)
                    .frame(minWidth: 820, minHeight: 600)
            }
    }
}

/// Central environment holding all app state
@MainActor
class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()
    
    // MARK: - Core Services
    
    @Published var pdfViewModel: PDFViewModel
    @Published var libraryViewModel: LibraryViewModel
    @Published var notesViewModel: NotesViewModel
    
    // MARK: - UI Services
    
    @Published var errorMessageManager: ErrorMessageManager
    @Published var enhancedToastCenter: EnhancedToastCenter
    
    // MARK: - UI State
    
    @Published var isShowingHelp = false
    @Published var isShowingSettings = false
    @Published var isShowingOnboarding = false
    @Published var showingInitError = false
    @Published var initializationError: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Initialize view models
        self.pdfViewModel = PDFViewModel()
        self.libraryViewModel = LibraryViewModel()
        self.notesViewModel = NotesViewModel()
        
        // Initialize services
        self.errorMessageManager = ErrorMessageManager.shared
        self.enhancedToastCenter = EnhancedToastCenter()
        
        // Set up communication between modules
        setupModuleCommunication()
        
        // Check for first launch
        checkFirstLaunch()
    }
    
    private func setupModuleCommunication() {
        // Library updates trigger PDF controller updates
        libraryViewModel.$items
            .sink { [weak self] items in
                self?.pdfViewModel.updateRecentDocuments(from: items)
            }
            .store(in: &cancellables)
    }
    
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let didSeeOnboarding = UserDefaults.standard.bool(forKey: "didSeeOnboarding")
        
        if !hasLaunchedBefore || !didSeeOnboarding {
            isShowingOnboarding = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }
    
    // MARK: - Window Management
    
    func openSettings() {
        isShowingSettings = true
    }
    
    func openHelp() {
        isShowingHelp = true
    }
}
