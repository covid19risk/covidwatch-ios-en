//
//  Created by Zsombor Szabo on 10/05/2020.
//  
//

import SwiftUI
import ExposureNotification

struct ReportingStep2: View {

    @EnvironmentObject var localStore: LocalStore

    @EnvironmentObject var userData: UserData

    @State var verificationCode: String = ""

    @State var symptomsStartDateString: String = ""

    @State var isSubmittingDiagnosis = false

    @State var isShowingNextStep = false

    @State var isShowingSymptonOnSetDatePicker = false

    var rkManager = RKManager(calendar: Calendar.current, minimumDate: Date()-14*24*60*60, maximumDate: Date(), mode: 0)

    let selectedDiagnosisIndex: Int

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    @State var isAsymptomatic = false

    init(selectedDiagnosisIndex: Int = 0) {
        self.selectedDiagnosisIndex = selectedDiagnosisIndex
        UIScrollView.appearance().keyboardDismissMode = .onDrag
    }

    var body: some View {

        ZStack(alignment: .top) {

            if !isShowingNextStep {
                reportingStep2.transition(.slide)
            } else {
                ReportingStep3().transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }

            HeaderBar(showMenu: false, showDismissButton: true)
        }
    }

    var reportingStep2: some View {

        ScrollView(.vertical, showsIndicators: false) {

            VStack(spacing: 0) {

                HowItWorksTitleText(text: Text(verbatim: String.localizedStringWithFormat(NSLocalizedString("STEP_X_OF_Y_TITLE", comment: ""), NSNumber(value: 2), NSNumber(value: 3)).uppercased()))
                    .padding(.top, .headerHeight)

                Text("REPORTING_VERIFY_TITLE")
                    .modifier(StandardTitleTextViewModifier())
                    .padding(.horizontal, 2 * .standardSpacing)

                Spacer(minLength: 2 * .standardSpacing)

                Group {
                    Spacer(minLength: 2 * .standardSpacing)

                    Text("VERIFICATION_CODE_QUESTION")
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundColor(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2 * .standardSpacing)

                    Spacer(minLength: .standardSpacing)

                    TextField(NSLocalizedString("VERIFICATION_CODE_TITLE", comment: ""), text: self.$verificationCode)
                        .padding(.horizontal, 2 * .standardSpacing)
                        .foregroundColor(Color.primary)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Spacer().frame(height: 2 * .standardSpacing)
                }

                Divider()
                    .padding(.horizontal, .standardSpacing)

                Group {
                    Spacer(minLength: 2 * .standardSpacing)

                    Text("SYMPTOMS_START_DATE_QUESTION")
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundColor(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2 * .standardSpacing)

                    Spacer(minLength: .standardSpacing)

                    Button(action: {
                        self.isShowingSymptonOnSetDatePicker.toggle()
                    }) {
                        TextField(NSLocalizedString("SELECT_DATE", comment: ""), text: self.$symptomsStartDateString)
                            .padding(.horizontal, 2 * .standardSpacing)
                            .foregroundColor(Color.primary)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .opacity(isAsymptomatic ? 0.5 : 1.0)
                            .disabled(true)
                    }
                    .disabled(isAsymptomatic)
                    .sheet(isPresented: self.$isShowingSymptonOnSetDatePicker, content: {
                        ZStack(alignment: .top) {
                            RKViewController(isPresented: self.$isShowingSymptonOnSetDatePicker, rkManager: self.rkManager)
                                .padding(.top, .headerHeight)

                            HeaderBar(showMenu: false, showDismissButton: true)
                                .environmentObject(self.userData)
                                .environmentObject(self.localStore)
                        }
                        .onDisappear {
                            self.symptomsStartDateString = self.rkManager.selectedDate == nil ? "" : self.dateFormatter.string(from: self.rkManager.selectedDate)
                            self.localStore.diagnoses[self.selectedDiagnosisIndex].symptomsStartDate = self.rkManager.selectedDate
                        }
                    })

                    Spacer(minLength: .standardSpacing)

                    HStack(alignment: .center) {

                        Button(action: {
                            withAnimation {
                                self.isAsymptomatic.toggle()
                                if self.isAsymptomatic {
                                    self.rkManager.selectedDate = nil
                                    self.symptomsStartDateString = ""
                                }
                            }
                        }) {
                            if self.isAsymptomatic {
                                Image("Checkbox Checked")
                            } else {
                                Image("Checkbox Unchecked")
                            }

                            Text("I have no symptoms.")
                                .foregroundColor(Color.secondary)
                        }
                    }.padding(.horizontal, 2 * .standardSpacing)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 2 * .standardSpacing)

                }

                Button(action: {

                    // Bypassing public health authority verification can be done:
                    // - on the app side, by configuring the app's info plist.
                    // - on the key server side, by configuring its database / authorizedapp table for this particular app.
                    let bypassPublicHealthAuthorityVerification = Bundle.main.infoDictionary?[.bypassPublicHealthAuthorityVerification] as? Bool ?? false

                    self.isSubmittingDiagnosis = true

                    let errorHandler: (Error) -> Void = { error in
                        self.isSubmittingDiagnosis = false
                        UIApplication.shared.topViewController?.present(
                            error,
                            animated: true,
                            completion: nil
                        )
                    }

                    if self.localStore.diagnoses[self.selectedDiagnosisIndex].verificationCode != self.verificationCode {
                        self.localStore.diagnoses[self.selectedDiagnosisIndex].isVerified = false
                    }
                    self.localStore.diagnoses[self.selectedDiagnosisIndex].verificationCode = self.verificationCode
                    self.localStore.diagnoses[self.selectedDiagnosisIndex].isAdded = true

                    let actionAfterCodeVerification = {

                        // To be able to calculate the hmac for the diagnosis keys, we need to request them now.
                        ExposureManager.shared.getDiagnosisKeys { (keys, error) in
                            if let error = error {
                                errorHandler(error)
                                return
                            }

                            guard let keys = keys, !keys.isEmpty else {
                                errorHandler(ENError(.internal))
                                return
                            }

                            // TODO: Set tranmission risk level for the diagnosis keys based on questions *before* sharing them with the key server.
                            keys.forEach { $0.transmissionRiskLevel = 6 }

                            let actionAfterVerificationCertificateRequest = {

                                // Step 8 of https://developers.google.com/android/exposure-notifications/verification-system
                                Server.shared.postDiagnosisKeys(
                                    keys,
                                    verificationPayload: self.localStore.diagnoses[self.selectedDiagnosisIndex].verificationCertificate,
                                    hmacKey: self.localStore.diagnoses[self.selectedDiagnosisIndex].hmacKey
                                ) { error in
                                    // Step 9
                                    // Since this is the last step, ensure `isSubmittingDiagnosis` is set to false.
                                    defer {
                                        self.isSubmittingDiagnosis = false
                                    }

                                    if let error = error {
                                        errorHandler(error)
                                        return
                                    }

                                    self.localStore.diagnoses[self.selectedDiagnosisIndex].isShared = true

                                    withAnimation {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        self.isShowingNextStep = true
                                    }
                                }
                            }

                            if !bypassPublicHealthAuthorityVerification {

                                do {
                                    let hmac = try ENVerificationUtils.calculateExposureKeyHMAC(
                                        forTemporaryExposureKeys: keys,
                                        secret: self.localStore.diagnoses[self.selectedDiagnosisIndex].hmacKey
                                    ).base64EncodedString()
                                    guard let longTermToken = self.localStore.diagnoses[self.selectedDiagnosisIndex].longTermToken else {
                                        // Shouldn't get here...
                                        self.isSubmittingDiagnosis = false
                                        return
                                    }
                                    // Step 6 of https://developers.google.com/android/exposure-notifications/verification-system
                                    Server.shared.getVerificationCertificate(forLongTermToken: longTermToken, hmac: hmac) { result in
                                        // Step 7
                                        switch result {
                                            case let .success(codableVerificationCertificateResponse):

                                                self.localStore.diagnoses[self.selectedDiagnosisIndex].verificationCertificate = codableVerificationCertificateResponse.certificate

                                                actionAfterVerificationCertificateRequest()

                                            case let .failure(error):
                                                // Something went wrong. Maybe the long-term token is not valid anymore?
                                                self.localStore.diagnoses[self.selectedDiagnosisIndex].isVerified = false
                                                errorHandler(error)
                                                return
                                        }
                                    }

                                } catch {
                                    errorHandler(error)
                                    return
                                }
                            } else {
                                actionAfterVerificationCertificateRequest()
                            }

                        }
                    }

                    if !self.localStore.diagnoses[self.selectedDiagnosisIndex].isVerified {

                        if bypassPublicHealthAuthorityVerification {

                            actionAfterCodeVerification()

                        } else {
                            // Step 4 of https://developers.google.com/android/exposure-notifications/verification-system
                            Server.shared.verifyCode(self.verificationCode) { result in
                                // Step 5
                                switch result {
                                    case let .success(codableVerifyCodeResponse):

                                        self.localStore.diagnoses[self.selectedDiagnosisIndex].isVerified = true
                                        self.localStore.diagnoses[self.selectedDiagnosisIndex].longTermToken = codableVerifyCodeResponse.token
                                        let formatter = ISO8601DateFormatter()
                                        formatter.formatOptions = [.withFullDate]
                                        self.localStore.diagnoses[self.selectedDiagnosisIndex].testDate = formatter.date(from: codableVerifyCodeResponse.testDate) ?? Date()
                                        self.localStore.diagnoses[self.selectedDiagnosisIndex].testType = codableVerifyCodeResponse.testType

                                        actionAfterCodeVerification()

                                    case let .failure(error):
                                        errorHandler(error)
                                        return
                                }
                            }
                        }

                    } else {
                        actionAfterCodeVerification()
                    }

                }) {
                    Group {
                        if !self.isSubmittingDiagnosis {
                            Text("REPORTING_VERIFY_NOTIFY_OTHERS")
                        } else {
                            ActivityIndicator(isAnimating: self.$isSubmittingDiagnosis) {
                                $0.color = .white
                            }
                        }
                    }.modifier(SmallCallToAction())
                }
                .disabled(self.isSubmittingDiagnosis)
                .padding(.top, 3 * .standardSpacing)
                .padding(.horizontal, 2 * .standardSpacing)
                .padding(.bottom, .standardSpacing)

                Image("Doctors Security")
                    .accessibility(hidden: true)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            }
        }

    }
}

struct ReportingCallCode_Previews: PreviewProvider {
    static var previews: some View {
        ReportingStep2()
    }
}