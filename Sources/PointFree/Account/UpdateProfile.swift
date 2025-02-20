import Dependencies
import Either
import EmailAddress
import Foundation
import HttpPipeline
import Models
import Parsing
import PointFreePrelude
import PointFreeRouter
import Prelude
import Stripe
import Tuple

func isValidEmail(_ email: EmailAddress) -> Bool {
  return email.rawValue.range(of: "^.+@.+$", options: .regularExpression) != nil
}

private func fetchStripeSubscription<A>(
  _ middleware: (
    @escaping Middleware<StatusLineOpen, ResponseEnded, T2<Stripe.Subscription?, A>, Data>
  )
)
  -> Middleware<StatusLineOpen, ResponseEnded, T2<Models.Subscription?, A>, Data>
{
  @Dependency(\.stripe) var stripe

  return { conn -> IO<Conn<ResponseEnded, Data>> in
    guard let subscription = get1(conn.data)
    else { return middleware(conn.map(over1(const(nil)))) }

    return IO { try? await stripe.fetchSubscription(subscription.stripeSubscriptionId) }
      .flatMap { conn.map(const($0 .*. conn.data.second)) |> middleware }
  }
}

let updateProfileMiddleware =
  requireUserAndProfileData
  <<< validateEmail
  <<< encryptPayload
  <<< fetchSubscriptionAndStripeSubscription
  <| updateProfileMiddlewareHandler

private let requireUserAndProfileData: MT<Tuple2<User?, ProfileData?>, Tuple2<User, ProfileData>> =
  filterMap(require1 >>> pure, or: loginAndRedirect)
  <<< filterMap(require2 >>> pure, or: redirect(to: .account()))

private let validateEmail: MT<Tuple2<User, ProfileData>, Tuple2<User, ProfileData>> = filter(
  get2 >>> \.email >>> isValidEmail,
  or: redirect(to: .account(), headersMiddleware: flash(.error, "Please enter a valid email."))
)

private func updateProfileMiddlewareHandler(
  conn: Conn<StatusLineOpen, Tuple4<Stripe.Subscription?, User, ProfileData, Encrypted<String>>>
) -> IO<Conn<ResponseEnded, Data>> {
  @Dependency(\.database) var database
  @Dependency(\.fireAndForget) var fireAndForget
  @Dependency(\.siteRouter) var siteRouter
  @Dependency(\.stripe) var stripe

  let (subscription, user, data, emailChangePayload) = lower(conn.data)

  let emailSettings = data.emailSettings.keys
    .compactMap(EmailSetting.Newsletter.init(rawValue:))

  let updateFlash: Middleware<HeadersOpen, HeadersOpen, Prelude.Unit, Prelude.Unit>
  if data.email.rawValue.lowercased() != user.email.rawValue.lowercased() {
    updateFlash = flash(.warning, "We've sent an email to \(user.email) to confirm this change.")
  } else {
    // TODO: why is unicode ‘ not encoded correctly?
    updateFlash = flash(.notice, "We've updated your profile!")
  }

  return EitherIO {
    try await database.updateUser(
      id: user.id,
      name: data.name,
      emailSettings: emailSettings
    )
    if data.email.rawValue.lowercased() != user.email.rawValue.lowercased() {
      await fireAndForget {
        _ = try await sendEmail(
          to: [user.email],
          subject: "Email change confirmation",
          content: inj2(confirmEmailChangeEmailView((user, data.email, emailChangePayload)))
        )
      }
    }
    if let customerId = subscription?.customer.id, let extraInvoiceInfo = data.extraInvoiceInfo {
      _ = try await stripe.updateCustomerExtraInvoiceInfo(customerId, extraInvoiceInfo)
    }
  }
  .run
  .flatMap(
    const(
      conn.map(const(unit))
        |> redirect(to: siteRouter.path(for: .account()), headersMiddleware: updateFlash)
    )
  )
}

private let fetchSubscriptionAndStripeSubscription:
  MT<
    Tuple3<User, ProfileData, Encrypted<String>>,
    Tuple4<Stripe.Subscription?, User, ProfileData, Encrypted<String>>
  > =
    fetchSubscription
    <<< fetchStripeSubscription

func encryptPayload<A>(
  _ middleware: @escaping Middleware<
    StatusLineOpen, ResponseEnded, T4<User, ProfileData, Encrypted<String>, A>, Data
  >
)
  -> Middleware<StatusLineOpen, ResponseEnded, T3<User, ProfileData, A>, Data>
{
  @Dependency(\.envVars) var envVars
  @Dependency(\.logger) var logger

  return { conn in
    let (user, data) = (get1(conn.data), get2(conn.data))

    guard
      let emailChangePayload = (try? emailChange.print((user.id, data.email)))
        .flatMap({ Encrypted(String($0), with: envVars.appSecret) })
    else {
      logger.log(.error, "Failed to encrypt email change for user: \(user.id)")

      return conn
        |> redirect(
          to: .account(),
          headersMiddleware: flash(.error, "An error occurred.")
        )
    }

    return conn.map(const(user .*. data .*. emailChangePayload .*. rest(conn.data)))
      |> middleware
  }
}

let emailChange = ParsePrint {
  UUID.parser().map(.representing(User.ID.self))
  "--POINT-FREE-BOUNDARY--"
  Rest().map(.string.representing(EmailAddress.self))
}

let confirmEmailChangeMiddleware:
  Middleware<StatusLineOpen, ResponseEnded, Encrypted<String>, Data> = { conn in
    @Dependency(\.database) var database
    @Dependency(\.envVars) var envVars
    @Dependency(\.logger) var logger

    guard
      let decrypted = conn.data.decrypt(with: envVars.appSecret),
      let (userId, newEmailAddress) = try? emailChange.parse(decrypted)
    else {
      logger.log(.error, "Failed to decrypt email change payload: \(conn.data.rawValue)")

      return conn
        |> redirect(
          to: .account(),
          headersMiddleware: flash(.error, "An error occurred.")
        )
    }

    parallel(
      EitherIO { try await database.fetchUserById(userId) }
        .flatMap { user in
          EitherIO {
            try await sendEmail(
              to: [newEmailAddress],
              subject: "Email change confirmation",
              content: inj2(emailChangedEmailView((user, newEmailAddress)))
            )
          }
        }
        .run
    )
    .run({ _ in })

    return EitherIO { try await database.updateUser(id: userId, email: newEmailAddress) }
      .run
      .flatMap(const(conn |> redirect(to: .account())))
  }
