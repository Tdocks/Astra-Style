import Foundation
import Supabase

extension LiveClosetRepository {
    /// Returns owner-owned garments created or purchased before the reviewed month's
    /// exclusive end. This is a history read only: it does not affect the
    /// active closet cache or guest item cap.
    public func fetchMonthlyHistoryItems(createdOrPurchasedBefore: Date) async throws -> [ClosetItem] {
        guard let ownerID = await currentUserID() else {
            throw AstraError.auth("Sign in again to load your Monthly Review history.")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAtUpperBound = formatter.string(from: createdOrPurchasedBefore)
        let purchaseDateUpperBound = DateFormatter.astraDay.string(from: createdOrPurchasedBefore)
        var rows: [ClosetItem] = []
        var offset = 0
        do {
            while true {
                try Task.checkCancellation()
                let page: [ClosetItem] = try await supabase.from("closet_items")
                    .select()
                    .eq("user_id", value: ownerID)
                    .or("created_at.lt.\(createdAtUpperBound),purchase_date.lt.\(purchaseDateUpperBound)")
                    .order("created_at", ascending: false)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + 499)
                    .execute()
                    .value
                rows.append(contentsOf: page)
                if page.count < 500 { break }
                offset += page.count
            }
            guard await currentUserID() == ownerID else {
                throw AstraError.auth("Your account changed while loading Monthly Review history.")
            }
            guard rows.allSatisfy({
                $0.userID == ownerID
                    && ($0.createdAt < createdOrPurchasedBefore
                        || $0.purchaseDate.map { $0 < createdOrPurchasedBefore } == true)
            }) else {
                throw AstraError.auth("Monthly Review history contained an item from another account.")
            }
            return rows
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load your closet history for Monthly Review.")
        }
    }

    public func fetchMonthlyVersatilityHistory(monthStart: Date) async throws -> MonthlyVersatilityHistory {
        guard let ownerID = await currentUserID() else {
            throw AstraError.auth("Sign in again to load your monthly score history.")
        }
        guard let currentMonth = Calendar.current.dateInterval(of: .month, for: monthStart)?.start,
              let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) else {
            throw AstraError.validation("That monthly score period is invalid.")
        }
        struct ScoreRow: Decodable, Sendable {
            let versatilityScore: Int
            let capturedAt: Date
            enum CodingKeys: String, CodingKey {
                case versatilityScore = "versatility_score"
                case capturedAt = "captured_at"
            }
        }
        func score(on date: Date) async throws -> Int? {
            let monthDate = DateFormatter.astraDay.string(from: date)
            let query = supabase.from("wardrobe_score_monthly_snapshots")
                .select("versatility_score, captured_at")
                .eq("user_id", value: ownerID)
                .eq("month_start", value: monthDate)
                .limit(1)
            let response: PostgrestResponse<[ScoreRow]> = try await query.execute()
            let rows = response.value
            guard let row = rows.first else { return nil }
            guard let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: date),
                  row.capturedAt >= date, row.capturedAt < monthEnd else { return nil }
            let value = row.versatilityScore
            guard (0...100).contains(value) else {
                throw AstraError.server("A saved monthly wardrobe score is invalid.")
            }
            return value
        }

        do {
            let monthScore = try await score(on: currentMonth)
            let previousScore = try await score(on: previousMonth)
            guard await currentUserID() == ownerID else {
                throw AstraError.auth("Your account changed while loading monthly score history.")
            }
            return MonthlyVersatilityHistory(monthScore: monthScore, previousScore: previousScore)
        } catch let error as AstraError {
            throw error
        } catch {
            throw AstraError.network("Couldn't load your monthly wardrobe score history.")
        }
    }
}
