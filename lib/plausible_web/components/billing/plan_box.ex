defmodule PlausibleWeb.Components.Billing.PlanBox do
  @moduledoc false

  use PlausibleWeb, :component

  require Plausible.Billing.Subscription.Status
  alias PlausibleWeb.Components.Billing.{PlanBenefits}
  alias Plausible.Billing.{Plan, Quota, Subscription}

  @plan_box_price_container_class "relative h-20 pt-4 max-h-20 whitespace-nowrap overflow-hidden"

  def standard(assigns) do
    highlight =
      cond do
        assigns.owned && assigns.recommended -> "Current"
        assigns.recommended -> "Recommended"
        true -> nil
      end

    assigns =
      assigns
      |> assign(:highlight, highlight)
      |> assign(:price_container_class, @plan_box_price_container_class)

    ~H"""
    <div
      id={"#{@kind}-plan-box"}
      class={[
        "shadow-lg border border-gray-200 dark:border-none bg-white rounded-xl px-6 sm:px-4 py-4 sm:py-3 dark:bg-gray-800",
        !@highlight && "dark:ring-gray-600",
        @highlight && "ring-2 ring-indigo-600 dark:ring-indigo-300"
      ]}
    >
      <div class="flex items-center justify-between gap-x-4">
        <h3 class={[
          "text-lg font-semibold leading-8",
          !@highlight && "text-gray-900 dark:text-gray-100",
          @highlight && "text-indigo-600 dark:text-indigo-300"
        ]}>
          {String.capitalize(to_string(@kind))}
        </h3>
        <.pill :if={@highlight} text={@highlight} />
      </div>
      <div>
        <div class={@price_container_class}>
          <.render_price_info available={@available} {assigns} />
        </div>
        <%= if @available do %>
          <.checkout id={"#{@kind}-checkout"} {assigns} />
        <% else %>
          <.contact_button class="bg-indigo-600 hover:bg-indigo-500 text-white" />
        <% end %>
      </div>
      <PlanBenefits.render benefits={@benefits} class="text-gray-600 dark:text-gray-100" />
    </div>
    """
  end

  def enterprise(assigns) do
    assigns = assign(assigns, :price_container_class, @plan_box_price_container_class)

    ~H"""
    <div
      id="enterprise-plan-box"
      class={[
        "rounded-xl px-6 sm:px-4 py-4 sm:py-3 bg-gray-900 shadow-xl dark:bg-gray-800",
        !@recommended && "dark:ring-gray-600",
        @recommended && "ring-4 ring-indigo-500 dark:ring-2 dark:ring-indigo-300"
      ]}
    >
      <div class="flex items-center justify-between gap-x-4">
        <h3 class={[
          "text-lg font-semibold leading-8",
          !@recommended && "text-white dark:text-gray-100",
          @recommended && "text-indigo-400 dark:text-indigo-300"
        ]}>
          Enterprise
        </h3>
        <span
          :if={@recommended}
          id="enterprise-highlight-pill"
          class="rounded-full ring-1 ring-indigo-500 px-2.5 py-1 text-xs font-semibold leading-5 text-indigo-400 dark:text-indigo-300 dark:ring-1 dark:ring-indigo-300/50"
        >
          Recommended
        </span>
      </div>
      <div class={@price_container_class}>
        <span class="text-3xl lg:text-2xl xl:text-3xl font-bold tracking-tight text-white dark:text-gray-100">
          Custom
        </span>
      </div>
      <.contact_button class="" />
      <PlanBenefits.render benefits={@benefits} class="text-gray-300 dark:text-gray-100" />
    </div>
    """
  end

  defp pill(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-x-4">
      <p
        id="highlight-pill"
        class="rounded-full bg-indigo-600/10 px-2.5 py-1 text-xs font-semibold leading-5 text-indigo-600 dark:text-indigo-300 dark:ring-1 dark:ring-indigo-300/50"
      >
        {@text}
      </p>
    </div>
    """
  end

  defp render_price_info(%{available: false} = assigns) do
    ~H"""
    <p id={"#{@kind}-custom-price"} class="flex items-baseline gap-x-1">
      <span class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        Custom
      </span>
    </p>
    <p class="h-4 mt-1"></p>
    """
  end

  defp render_price_info(assigns) do
    ~H"""
    <.price_tag kind={@kind} selected_interval={@selected_interval} plan_to_render={@plan_to_render} />
    <div
      id={"#{@kind}-vat-notice"}
      class="absolute top-[32px] sm:top-[29px] md:top-[32px] lg:top-[29px] xl:top-[32px] right-0 text-xs text-gray-500"
    >
      + VAT
      <span class="hidden sm:inline lg:hidden xl:inline">
        if applicable
      </span>
    </div>
    """
  end

  defp price_tag(%{selected_interval: :monthly} = assigns) do
    monthly_cost =
      case assigns.plan_to_render do
        %{monthly_cost: nil} -> "N/A"
        %{monthly_cost: monthly_cost} -> Plausible.Billing.format_price(monthly_cost)
      end

    assigns = assign(assigns, :monthly_cost, monthly_cost)

    ~H"""
    <p class="flex items-baseline gap-x-1">
      <span
        id={"#{@kind}-price-tag-amount"}
        class="text-3xl lg:text-2xl xl:text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100"
      >
        {@monthly_cost}
      </span>
      <span
        id={"#{@kind}-price-tag-interval"}
        class="text-sm font-semibold leading-6 text-gray-600 dark:text-gray-500"
      >
        /month
      </span>
    </p>
    """
  end

  defp price_tag(%{selected_interval: :yearly} = assigns) do
    monthly_cost =
      case assigns.plan_to_render do
        %{monthly_cost: nil} -> "N/A"
        %{monthly_cost: monthly_cost} -> Plausible.Billing.format_price(monthly_cost)
      end

    {yearly_cost, monthly_cost_with_discount} =
      case assigns.plan_to_render do
        %{yearly_cost: nil} ->
          {"N/A", "N/A"}

        %{yearly_cost: yearly_cost} ->
          {
            Plausible.Billing.format_price(yearly_cost),
            Plausible.Billing.format_price(Money.div!(yearly_cost, 12))
          }
      end

    assigns =
      assigns
      |> assign(:monthly_cost, monthly_cost)
      |> assign(:yearly_cost, yearly_cost)
      |> assign(:monthly_cost_with_discount, monthly_cost_with_discount)

    ~H"""
    <div class="grid grid-cols-[max-content_1fr]">
      <span
        id={"#{@kind}-price-tag-amount"}
        class="text-3xl lg:text-2xl xl:text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100"
      >
        {@yearly_cost}
      </span>

      <span
        id={"#{@kind}-price-tag-interval"}
        class="text-sm font-semibold leading-6 text-gray-600 pl-1 self-end"
      >
        /year
      </span>

      <div class="font-bold tracking-tight text-sm self-center">
        <span
          id={"#{@kind}-discount-price-tag-strikethrough-amount"}
          class="line-through tracking-tight text-gray-500 dark:text-gray-600"
        >
          {@monthly_cost}
        </span>
        <span id={"#{@kind}-discount-price-tag-amount"} class="ml-1 text-gray-900 dark:text-gray-100">
          {@monthly_cost_with_discount}
        </span>
      </div>

      <span class="text-sm font-semibold text-gray-600 pl-1 self-center">
        /month
      </span>
    </div>
    """
  end

  defp checkout(assigns) do
    paddle_product_id = get_paddle_product_id(assigns.plan_to_render, assigns.selected_interval)
    change_plan_link_text = change_plan_link_text(assigns)

    subscription =
      Plausible.Teams.Billing.get_subscription(assigns.current_team)

    billing_details_expired =
      Subscription.Status.in?(subscription, [
        Subscription.Status.paused(),
        Subscription.Status.past_due()
      ])

    subscription_deleted = Subscription.Status.deleted?(subscription)
    usage_check = check_usage_within_plan_limits(assigns)

    {checkout_disabled, disabled_message} =
      cond do
        not Quota.eligible_for_upgrade?(assigns.usage) ->
          {true, nil}

        change_plan_link_text == "Currently on this plan" && not subscription_deleted ->
          {true, nil}

        usage_check != :ok ->
          {true, "Your usage exceeds this plan"}

        billing_details_expired ->
          {true, "Please update your billing details first"}

        true ->
          {false, nil}
      end

    exceeded_plan_limits =
      case usage_check do
        {:error, {:over_plan_limits, limits}} ->
          limits

        _ ->
          []
      end

    feature_usage_check = Quota.ensure_feature_access(assigns.usage, assigns.plan_to_render)

    assigns =
      assigns
      |> assign(:paddle_product_id, paddle_product_id)
      |> assign(:change_plan_link_text, change_plan_link_text)
      |> assign(:checkout_disabled, checkout_disabled)
      |> assign(:disabled_message, disabled_message)
      |> assign(:exceeded_plan_limits, exceeded_plan_limits)
      |> assign(:confirm_message, losing_features_message(feature_usage_check))

    ~H"""
    <%= if @owned_plan && Plausible.Billing.Subscriptions.resumable?(@current_team.subscription) do %>
      <.change_plan_link {assigns} />
    <% else %>
      <PlausibleWeb.Components.Billing.paddle_button
        user={@current_user}
        team={@current_team}
        {assigns}
      >
        Upgrade
      </PlausibleWeb.Components.Billing.paddle_button>
    <% end %>
    <div :if={@exceeded_plan_limits != [] && @disabled_message} class="flex flex-col items-center">
      <.tooltip>
        <div class="h-0 text-sm">
          <div class="flex items-center text-red-700 dark:text-red-500 justify-center">
            {@disabled_message}
            <Heroicons.information_circle class="hidden sm:block w-5 h-5 sm:ml-2" />
          </div>
        </div>
        <:tooltip_content>
          Your usage exceeds the following limit(s):<br /><br />
          <p :for={limit <- @exceeded_plan_limits}>
            {Phoenix.Naming.humanize(limit)}<br />
          </p>
        </:tooltip_content>
      </.tooltip>
    </div>
    <div
      :if={@disabled_message && @exceeded_plan_limits == []}
      class="pt-2 text-sm w-full text-red-700 dark:text-red-500 text-center"
    >
      {@disabled_message}
    </div>
    """
  end

  defp check_usage_within_plan_limits(%{available: false}) do
    {:error, :plan_unavailable}
  end

  defp check_usage_within_plan_limits(%{
         available: true,
         usage: usage,
         current_team: current_team,
         plan_to_render: plan
       }) do
    # At this point, the user is *not guaranteed* to have a team,
    # with ongoing trial.
    trial_active_or_ended_recently? =
      not is_nil(current_team) and not is_nil(current_team.trial_expiry_date) and
        Plausible.Teams.trial_days_left(current_team) >= -10

    limit_checking_opts =
      cond do
        current_team && current_team.allow_next_upgrade_override ->
          [ignore_pageview_limit: true]

        trial_active_or_ended_recently? && plan.volume == "10k" ->
          [pageview_allowance_margin: 0.3]

        trial_active_or_ended_recently? ->
          [pageview_allowance_margin: 0.15]

        true ->
          []
      end

    Quota.ensure_within_plan_limits(usage, plan, limit_checking_opts)
  end

  defp get_paddle_product_id(%Plan{monthly_product_id: plan_id}, :monthly), do: plan_id
  defp get_paddle_product_id(%Plan{yearly_product_id: plan_id}, :yearly), do: plan_id

  defp change_plan_link_text(
         %{
           owned_plan: %Plan{kind: from_kind, monthly_pageview_limit: from_volume},
           plan_to_render: %Plan{kind: to_kind, monthly_pageview_limit: to_volume},
           current_interval: from_interval,
           selected_interval: to_interval
         } = _assigns
       ) do
    cond do
      from_kind in [:growth, :business] && to_kind == :starter ->
        "Downgrade to Starter"

      from_kind == :business && to_kind == :growth ->
        "Downgrade to Growth"

      from_kind == :starter && to_kind == :growth ->
        "Upgrade to Growth"

      from_kind in [:starter, :growth] && to_kind == :business ->
        "Upgrade to Business"

      from_volume == to_volume && from_interval == to_interval ->
        "Currently on this plan"

      from_volume == to_volume ->
        "Change billing interval"

      from_volume > to_volume ->
        "Downgrade"

      true ->
        "Upgrade"
    end
  end

  defp change_plan_link_text(_), do: nil

  defp change_plan_link(assigns) do
    confirmed =
      if assigns.confirm_message, do: "confirm(\"#{assigns.confirm_message}\")", else: "true"

    assigns = assign(assigns, :confirmed, confirmed)

    ~H"""
    <button
      id={"#{@kind}-checkout"}
      onclick={"if (#{@confirmed}) {window.location = '#{Routes.billing_path(PlausibleWeb.Endpoint, :change_plan_preview, @paddle_product_id)}'}"}
      class={[
        "w-full mt-6 block rounded-md py-2 px-3 text-center text-sm font-semibold leading-6 text-white",
        !@checkout_disabled && "bg-indigo-600 hover:bg-indigo-500",
        @checkout_disabled && "pointer-events-none bg-gray-400 dark:bg-gray-600"
      ]}
    >
      {@change_plan_link_text}
    </button>
    """
  end

  defp losing_features_message(:ok), do: nil

  defp losing_features_message({:error, {:unavailable_features, features}}) do
    features_list_str =
      features
      |> Enum.map(fn feature_mod -> feature_mod.display_name() end)
      |> PlausibleWeb.TextHelpers.pretty_join()

    "This plan does not support #{features_list_str}, which you have been using. By subscribing to this plan, you will not have access to #{if length(features) == 1, do: "this feature", else: "these features"}."
  end

  defp contact_button(assigns) do
    ~H"""
    <.link
      href="https://plausible.io/contact"
      class={[
        "mt-6 block rounded-md py-2 px-3 text-center text-sm font-semibold leading-6 bg-gray-800 hover:bg-gray-700 text-white dark:bg-indigo-600 dark:hover:bg-indigo-500",
        @class
      ]}
    >
      Contact us
    </.link>
    """
  end
end
