import FooTubeCore
import Testing

@Suite("Skip policy during playback")
struct SkipPolicyTests {
    let intro = SkipSegment(id: "intro", category: .intro, start: 0, end: 10)
    let sponsor = SkipSegment(id: "sponsor", category: .sponsor, start: 60, end: 90)

    @Test func `sponsor segment is auto-skipped once when playback enters it`() {
        var policy = SkipPolicy(segments: [intro, sponsor])
        #expect(policy.evaluate(at: 59) == .none)
        #expect(policy.evaluate(at: 60.2) == .autoSkip(sponsor))
        #expect(policy.evaluate(at: 90.1) == .none)
    }

    @Test func `seeking back into an auto-skipped sponsor does not skip again`() {
        var policy = SkipPolicy(segments: [sponsor])
        #expect(policy.evaluate(at: 61) == .autoSkip(sponsor))
        #expect(policy.evaluate(at: 70) == .none)
    }

    @Test func `other categories are offered while inside and not after leaving`() {
        var policy = SkipPolicy(segments: [intro, sponsor])
        #expect(policy.evaluate(at: 0.5) == .offer(intro))
        #expect(policy.evaluate(at: 9) == .offer(intro))
        #expect(policy.evaluate(at: 10.5) == .none)
    }

    @Test func `no offer or skip in the last half second of a segment`() {
        var policy = SkipPolicy(segments: [intro, sponsor])
        #expect(policy.evaluate(at: 9.7) == .none)
        #expect(policy.evaluate(at: 89.6) == .none)
    }

    @Test func `an offered segment stops being offered once skipped by the user`() {
        var policy = SkipPolicy(segments: [intro])
        #expect(policy.evaluate(at: 2) == .offer(intro))
        policy.markSkipped(intro)
        #expect(policy.evaluate(at: 3) == .none)
    }

    @Test func `overlapping segments prefer the auto-skipping sponsor`() {
        let overlappingIntro = SkipSegment(id: "intro2", category: .intro, start: 55, end: 70)
        var policy = SkipPolicy(segments: [overlappingIntro, sponsor])
        #expect(policy.evaluate(at: 65) == .autoSkip(sponsor))
    }
}
