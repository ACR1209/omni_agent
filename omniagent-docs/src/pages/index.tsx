import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero', styles.heroBanner)}>
      <div className={styles.heroGlow} />
      <div className="container">
        <div className={styles.heroGrid}>
          <div className={styles.heroCopy}>
            {/* x-release-please-start-version */}
            <span className={styles.heroBadge}>v0.1.9 &middot; Rails engine</span>
            {/* x-release-please-end */}
            <Heading as="h1" className={styles.heroTitle}>
              {siteConfig.title}
            </Heading>
            <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
            <p className={styles.heroLead}>
              Generate agentic code the Rails way. Opinionated DSL for agents,
              tools, prompts, and provider config &mdash; scaffolded with a
              single generator.
            </p>
            <div className={styles.buttons}>
              <Link className="button button--primary button--lg" to="/docs/intro">
                Get Started &rarr;
              </Link>
              <Link
                className={clsx('button button--secondary button--lg', styles.githubButton)}
                to="https://github.com/ACR1209/omni_agent">
                View on GitHub
              </Link>
            </div>
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="ruby" title="research_agent.rb">
{`class ResearchAgent < OmniAgent::Agent
  use_model "gpt-4o-mini"

  before_generation :set_current_user

  def set_current_user
    @user = "Test User"
  end
end

ResearchAgent.new.run("Hello!")`}
            </CodeBlock>
          </div>
        </div>
      </div>
    </header>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="Omni Agent is a Rails engine gem for building application-native AI agents with tools, the Rails way.">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
