import Foundation

extension Episode {
  public static let ep136_animations = Episode(
    blurb: """
Nearly everything we've done so far with animations works just fine with the Composable Architecture, but there are a few rough edges that need to be smoothed out. In the process of smoothing out those edges we will come across a really amazing application of transforming schedulers.
""",
    codeSampleDirectory: "0136-swiftui-animation-pt2",
    exercises: _exercises,
    id: 136,
    image: "https://i.vimeocdn.com/video/TODO.jpg",
    length: 44*60 + 38,
    permission: .subscriberOnly,
    publishedAt: .init(timeIntervalSince1970: 1613973600),
    references: [
      .init(
        author: "Point-Free",
        blurb: "A word game by us, written in the Composable Architecture.",
        link: "https://www.isowords.xyz",
        publishedAt: nil,
        title: "isowords"
      ),
    ],
    sequence: 136,
    subtitle: "The Basics",
    title: "SwiftUI Animation",
    trailerVideo: .init(
      bytesLength: 60558782,
      vimeoId: 514083267,
      vimeoSecret: "6e374c14961b4c8308d0219a18868e79d9302a8c"
    )
  )
}

private let _exercises: [Episode.Exercise] = [
  .init(
    problem: #"""
    If you tap "cycle colors" and then immediately tap "reset" any in-flight effects will still animate the circle's color. Add effect cancellation logic to the reducer so that the "reset" button cancels such in-flight effects.
    """#,
    solution: nil
  ),
  .init(
    problem: #"""
    Our application is simple in that most of the actions fed to the reducer mutate state simply. Reduce the number of explicitly-defined actions in `AppAction` to use the `BindingAction` form helper instead.
    """#,
    solution: nil
  ),
]
