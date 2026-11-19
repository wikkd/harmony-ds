import { Dim, Motion } from '../common/DesignTokens';
import { DrawerButton, StatusCapsule } from '../components/titlebar/TopControls';
import { Sider } from '../components/sider/Sider';
import { ChatView } from './ChatView';

/**
 * 主页壳：主内容（ChatView）+ 抽屉/常驻侧栏。
 * 宽屏（≥840vp）侧栏常驻，主内容用 padding 让位（布局级）；
 * 窄屏侧栏抽屉化，主内容随 drawerProgress 用 translate 推出，拖动跟手、松手吸附。
 */
@Component
export struct HomePage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('safeBottomVp') safeBottom: number = 0;
  /** 抽屉进度 0 收起 / 1 展开：驱动侧栏滑入与主内容推出，AppStorage 供 Index.onBackPress 读取 */
  @StorageLink('drawerProgress') drawerProgress: number = 0;
  @StorageLink('bpWindowWidth') winWidth: number = 0;
  /** 拖动过程中的起始进度与有效标记 */
  private dragBase: number = 0;
  private dragActive: boolean = false;

  private isWide(): boolean {
    return this.winWidth >= Dim.siderPermanentBp;
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      // 主内容：抽屉展开时被整体向右推出屏幕，收起时拉回
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            ChatView({
              safeBottom: this.safeBottom,
              onNeedKey: (): void => {
                this.pathStack.pushPathByName('settings', null);
              },
            })
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.app_bg'))
          // 聊天页延伸到物理上下边缘：列表视口与输入面板都铺满，底部不留安全区死空间
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 顶部浮层控件行：左抽屉钮、右胶囊（毛玻璃半遮挡）。
          // 用 Row+padding 定位——position 下的 margin 不生效
          Row() {
            DrawerButton({
              onTap: (): void => {
                if (this.drawerProgress > 0.5) {
                  this.closeDrawer();
                } else {
                  this.openDrawer();
                }
              },
            })
              .visibility(this.isWide() ? Visibility.None : Visibility.Visible)
            Blank()
            StatusCapsule({
              onOpenSettings: (): void => {
                this.pathStack.pushPathByName('settings', null);
              },
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ left: 12, right: 12, top: 12 })
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      // 宽屏常驻侧栏必须用 padding 让位（布局级）：translate 不改布局宽度，
      // width('100%') 子件仍按全窗宽居中/铺开，欢迎态与输入面板会整体右偏、右缘被裁。
      // translate 只承担窄屏抽屉动画。
      .padding({ left: this.isWide() ? Dim.siderWidth : 0 })
      .translate({ x: this.contentShift() })

      // 抽屉展开期间的透明触控层：无压暗、无渐变，仅用于点击空白处收起抽屉
      if (!this.isWide() && this.drawerProgress > 0.01) {
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onClick(() => {
            this.closeDrawer();
          })
      }

      // 侧栏抽屉：实底面板直接从屏幕左缘拉出（宽屏常驻），无投影无渐变，边缘干净
      Column() {
        Sider({
          onSessionSelected: () => {
            if (!this.isWide()) {
              this.closeDrawer();
            }
          },
        })
      }
      .width(Dim.siderWidth)
      .height('100%')
      .backgroundColor($r('app.color.sider_bg'))
      .translate({ x: this.siderShift() })
      // 上下扩展只作用于绘制：灰底铺进状态栏/手势条区域，内容仍在安全区内排布
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .visibility(this.isWide() || this.drawerProgress > 0.01 ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    // 整页沉浸到物理边缘：状态栏与手势条区域都铺底色，不再有安全区分界线
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 平行手势：横向拖动驱动抽屉，不拦截列表纵向滚动与子件点击
    .parallelGesture(this.drawerPan())
  }

  /** 主内容水平位移：宽屏由 padding 让位（位移 0），窄屏随抽屉进度向右推出 */
  private contentShift(): number {
    return this.isWide() ? 0 : Dim.siderWidth * this.drawerProgress;
  }

  /** 侧栏水平位移：收起时完全藏在屏幕左缘外 */
  private siderShift(): number {
    return this.isWide() ? 0 : (this.drawerProgress - 1) * Dim.siderWidth;
  }

  private openDrawer(): void {
    // 松手吸附用弹簧曲线：可打断、继承手势速度（官方引力动效「控制感」）
    this.getUIContext().animateTo({ curve: Motion.spring }, (): void => {
      this.drawerProgress = 1;
    });
  }

  private closeDrawer(): void {
    this.getUIContext().animateTo({ curve: Motion.spring }, (): void => {
      this.drawerProgress = 0;
    });
  }

  /** 抽屉横向拖动：展开时任意位置拖回，收起时仅左缘 80vp 内可拖出；松手按进度/速度吸附 */
  private drawerPan(): PanGestureInterface {
    return PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 10 })
      .onActionStart((e: GestureEvent) => {
        this.dragBase = this.drawerProgress;
        const startX = e.fingerList.length > 0 ? e.fingerList[0].globalX : 0;
        this.dragActive = !this.isWide() && (this.dragBase > 0.01 || startX <= 80);
      })
      .onActionUpdate((e: GestureEvent) => {
        if (!this.dragActive || this.isWide()) {
          return;
        }
        const p = this.dragBase + e.offsetX / Dim.siderWidth;
        this.drawerProgress = Math.min(Math.max(p, 0), 1);
      })
      .onActionEnd((e: GestureEvent) => {
        if (!this.dragActive) {
          return;
        }
        this.dragActive = false;
        if (this.drawerProgress > 0.5 || e.velocityX > 360) {
          this.openDrawer();
        } else {
          this.closeDrawer();
        }
      })
      .onActionCancel(() => {
        if (!this.dragActive) {
          return;
        }
        this.dragActive = false;
        if (this.drawerProgress > 0.5) {
          this.openDrawer();
        } else {
          this.closeDrawer();
        }
      });
  }
}
