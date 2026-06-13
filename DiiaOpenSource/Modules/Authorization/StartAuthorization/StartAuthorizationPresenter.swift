import UIKit
import ReactiveKit
import DiiaMVPModule
import DiiaCommonTypes
import DiiaUIComponents
import DiiaCommonServices
import DiiaAuthorization
import DiiaAuthorizationPinCode
import DiiaAuthorizationMethods

protocol StartAuthorizationAction: BasePresenter {
    func showPersonalDataProcessing()
    func viewWillAppear()
}

final class StartAuthorizationPresenter: StartAuthorizationAction {
    
    unowned var view: StartAuthorizationView
    private let apiClient: AuthorizationApiClient
    private let authFlow: AuthFlow
    private let storeHelper: StoreHelperProtocol = StoreHelper.instance
    private let bag = DisposeBag()

    private var checkmarks: [CheckmarkViewModel] = []
    private var processId: String?

    // MARK: - Init
    init(view: StartAuthorizationView, authApiClient: AuthorizationApiClient) {
        self.view = view
        self.apiClient = authApiClient
        self.authFlow = .login
    }

    // MARK: - Public Methods
    func configureView() {
        storeHelper.save(true, type: Bool.self, forKey: .hasAppBeenLaunchedBefore)
        setupAgreement()
    }

    func viewWillAppear() {
        showAuthMethods()
    }

    func showPersonalDataProcessing() {
        CommunicationHelper.url(urlString: Constants.personalDataProcessingUrl)
    }

    // MARK: - Private methods
    /// Offline (frontend-only) auth methods list. No backend call is made:
    /// the Bank-ID button leads straight to pincode creation.
    private func showAuthMethods() {
        let authMethods: [AuthMethod] = [.bankId]

        let authMethodItems = authMethods.map { authMethod in
            let viewModel = DSListItemViewModel(
                leftBigIcon: authMethod.icon,
                title: authMethod.label ?? R.Strings.authorization_methods_title.localized(),
                onClick: { [weak self] in
                    self?.createPincode()
                }
            )
            viewModel.accessibilityLabel = authMethod.accessibilityLabel
            return viewModel
        }
        view.setAuthMethods(with: DSListViewModel(
            title: R.Strings.authorization_methods_title.localized(),
            items: authMethodItems)
        )
        view.setLoadingState(.ready)
    }

    private func setupAgreement() {
        self.checkmarks = [
            CheckmarkViewModel(
                text: R.Strings.authorization_data_processing_agreement.localized(),
                isChecked: true,
                componentId: Constants.checkmarkComponentId)
        ]
        let viewModel = BorderedCheckmarksViewModel(checkmarks: self.checkmarks)
        viewModel.onClick = { [weak self] in
            guard let self = self else { return }
            let isAvailable = self.checkmarks.contains(where: { $0.isChecked })
            self.view.setAvailability(isAvailable)
        }
        view.setCheckmarks(with: viewModel)
    }

    // MARK: - Navigation
    private func createPincode() {
        // Frontend-only stub: mark the user as authorized so that on the next
        // launch AppRouter routes straight to pincode -> main tab bar
        // instead of returning to this screen.
        StoreHelper.instance.save(Constants.offlineAuthToken, type: String?.self, forKey: .authToken)
        view.open(module: StartAuthorizationPresenter.userLoginSuccessModule())
    }
}

// MARK: - Constants
extension StartAuthorizationPresenter {
    private enum Constants {
        static let personalDataProcessingUrl = "https://diia.gov.ua/app_policy"
        static let checkmarkComponentId = "checkbox_conditions_auth"
        static let offlineAuthToken = "offline_stub_token"
    }
}

extension StartAuthorizationPresenter {
    /// completion handler wiith app level specific code for using after successfull authorization. Reused in Authorization Core
    static func userLoginSuccessModule() -> CreatePinCodeModule {
        return CreatePinCodeModule(
            viewModel: PinCodeViewModel(
                pinCodeLength: AppConstants.App.defaultPinCodeLength,
                createDetails: R.Strings.authorization_new_pin_details.localized(),
                repeatDetails: R.Strings.authorization_repeat_pin_details.localized(),
                authFlow: .login,
                completionHandler: { (pincode, view) in
                    ServicesProvider.shared.authService.setPincode(pincode: pincode)
                    switch BiometryHelper.biometricType() {
                    case .none:
                        AppRouter.instance.open(module: MainTabBarModule(), needPincode: false, asRoot: true)
                        AppRouter.instance.didFinishStartingWithPincode = true
                    default:
                        StoreHelper.instance.save(false, type: Bool.self, forKey: .isBiometryEnabled)
                        view.open(module: BiometryRequestModule(viewModel: .default(authFlow: .login)))
                    }
                }
            )
        )
    }
}
