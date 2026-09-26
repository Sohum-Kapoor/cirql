"""Cirql — entry point.

Server: schema.sv.jac (nodes/edges) and walkers.sv.jac (API).
Client: frontend.cl.jac + frontend.impl.jac, components/, pages/.
See AGENTS.md for ownership and workflow.
"""

import from walkers { Ping, GetMe, ListPeople, ListGoals, DevAddPerson }
import from onboard { OnboardMe }
import from capture { Capture }
import from gaps { GapFinder, GapDevSeed }
import from goals { GoalRank, SetGoal, CloseGoal }
import from scoring { ScoreAgainstNeed }
import from intros { AdvanceIntroduction, DevProposeIntroduction }
import from exchange { PostRequest, ListIncomingRequests, ReplyToRequest, ListMyRequests, ApproveReply, OptIn, Reveal, ClaimReveal, DeclineRequest, DeclineReply, ListMyReplies, DevMakeCard, DevSeedMatch }
import from reverse { WhoNeedsWhatIHave }
import from cards { PublishCard, get_card }
import from reads { Receipt, ListPromises, CompletePromise, GraphView }
import from imports { ImportPeople, ConfirmPerson, SkipPerson }
import from drafts { DraftFollowUp }
import from recall { Recall }
import from freshness { FreshnessSweep, ReconfirmFact, ReconfirmIntent }
import from forget { Forget }
import from handshake { OfferHandshake, ListHandshakes, AcceptHandshake, DeclineHandshake }
import from tend { Tend }
import from voice { Transcribe }
import from paths { PathFinder }
import from merge { ProposeMerges, MergePeople, UndoMerge }
import from plan { GamePlan }
import from health { NetworkHealth }
import from noted { NotedCard, ApplyCorrection }
import from serendipity { Serendipity }
import from vision { CaptureImage }
import from person { PersonDetail, Brief }
import from enrich { Enrich }
import from export { ExportGraph }
import from edits { UpdatePerson, UpdatePromise }

# Client-side UI
cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
